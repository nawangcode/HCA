USE [RMDW]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[prHCA3]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[prHCA3]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[prHCA3] 
@date DATETIME =NULL,
@startTime DATETIME =NULL,
@endTime DATETIME =NULL,
@unit NVARCHAR(50)=NULL,
@levels NVARCHAR(MAX)=NULL
AS
BEGIN

	IF @date IS NULL
	SET @date = GETDATE() - 1

	IF @startTime IS NULL
	SET @startTime ='07:00:00'

	IF @endTime IS NULL
	SET @endTime = '08:00:00'

	DECLARE @FACILITY INT
	SET @FACILITY =1

	DECLARE @OUT INT
	SET @OUT = 10

	DECLARE @IN INT
	SET @IN = 120

	SELECT DISTINCT L.Location_Key, L.Room_Name+'-'+L.Bed_Name AS RoomBed
	INTO #LOCATION
	FROM [dbo].[DimZone] Z 
	JOIN [dbo].[DimZoneLocation] ZL ON ZL.Zone_Key = Z.Zone_Key AND @date BETWEEN CAST(FLOOR(CAST(ZL.Activate_Date AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(ZL.Inactivate_Date AS FLOAT ) ) AS DATETIME )
	JOIN [dbo].[DimLocation] L ON L.Location_Key = ZL.Location_Key AND @date BETWEEN CAST(FLOOR(CAST(L.Activate_Date AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(L.Inactivate_Date AS FLOAT ) ) AS DATETIME )
	WHERE Z.Zone_Name = LTRIM(RTRIM(@unit)) AND @date BETWEEN CAST(FLOOR(CAST(Z.Activate_Date AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(Z.Inactivate_Date AS FLOAT ) ) AS DATETIME )
	AND Z.Facility_Key = @FACILITY AND L.Bed_ID > 0 AND L.Bed_Name <> '0' AND (CAST(L.Bed_Name AS INT) < 100 OR CAST(L.Bed_Name AS INT) > 199)

	DECLARE @Level TABLE
	(
		StaffLevelKey INT,
		IsStaff	BIT
	)

	-- GET STAFF KEY WITH SELECTED SERVICE LEVEL
	;WITH LevelFilter(j,Level_Name)	AS
	(
		SELECT	
		CHARINDEX(',', @levels+','),   
		SUBSTRING(@levels, 1, CHARINDEX(',',@levels+',')-1)
		UNION ALL
		SELECT	
		CHARINDEX(',', @levels+',', j+1),
		SUBSTRING(@levels, j+1, CHARINDEX(',',@levels+',',j+1)-(j+1))
		FROM	LevelFilter
		WHERE	CHARINDEX(',',@levels+',',j+1) <> 0
	)
	
	INSERT INTO @Level
	SELECT DISTINCT SL.Service_Level_Key, 0
	FROM LevelFilter L
	JOIN [dbo].[DimServiceLevel] SL ON SL.Service_Level_Name = LTRIM(RTRIM(L.Level_Name)) AND @date BETWEEN CAST(FLOOR(CAST(SL.RowStartDate AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(SL.RowEndDate AS FLOAT ) ) AS DATETIME )
	WHERE SL.Facility_Key = @FACILITY AND SL.Service_Level_Key > 0

	INSERT INTO @Level
	SELECT DISTINCT SSL.Staff_Key, 1
	FROM @Level L
	JOIN [dbo].[DimStaffServiceLevel] SSL ON SSL.Service_Level_Key = L.StaffLevelKey AND @date BETWEEN CAST(FLOOR(CAST(SSL.Activate_Date AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(SSL.Inactivate_Date AS FLOAT ) ) AS DATETIME )
	WHERE SSL.Staff_Key > 0
 
 --SELECT * FROM #LOCATION
 --SELECT * FROM @Level
 --RETURN

 -- GET EVENTS
	SELECT F.Location_Key, RoomBed, F.Staff_Key, F.Service_Level_Key, Group_Time_Key as StartTimeKey, Group_Time_Key - In_Room_Duration as EndTimeKey, In_Room_Duration, Event_Time
	,ROW_NUMBER() OVER (PARTITION BY F.Location_Key, F.Staff_Key order by Group_Time_Key DESC) AS ROW
	INTO #EVENTS
	FROM [dbo].[FactEventActivity] F
	JOIN #LOCATION L ON F.Location_Key = L.Location_Key
	JOIN @Level S ON (F.Staff_Key = S.StaffLevelKey AND S.IsStaff = 1) OR (F.Service_Level_Key = S.StaffLevelKey AND S.IsStaff = 0)
	WHERE F.Group_Date_Key = CONVERT(VARCHAR(8), @date, 112) AND In_Room_Duration > 0

--SELECT * FROM #EVENTS
-- return
	 ;WITH E(StartTimeKey, EndTimeKey, ENDROW, STARTROW, DURATION, LOCATION, STAFF, SERVICELEVEL, ROOMBED)
	AS
	(
		SELECT StartTimeKey, EndTimeKey, ROW, ROW, In_Room_Duration, Location_Key, Staff_Key, Service_Level_Key, RoomBed
		FROM #EVENTS
		UNION ALL
		SELECT E.StartTimeKey, D.EndTimeKey, D.ROW, IIF(E.STARTROW<E.ENDROW, E.STARTROW, E.ENDROW), D.In_Room_Duration+E.DURATION, Location_Key, Staff_Key, D.Service_Level_Key, D.RoomBed
		FROM #EVENTS D
		JOIN E ON E.EndTimeKey - D.StartTimeKey < @OUT AND D.ROW = E.ENDROW + 1 AND E.LOCATION = D.Location_Key AND E.STAFF = D.Staff_Key AND E.SERVICELEVEL = D.Service_Level_Key
	)

--SELECT * FROM  E
--return
	SELECT StartTimeKey, LOCATION, ROOMBED
	INTO #ALLEVENTS
	FROM 
	(
		SELECT MAX(StartTimeKey) AS StartTimeKey, MAX(DURATION) DURATION, MAX(ROOMBED) AS ROOMBED, LOCATION

		FROM
		(
			SELECT MAX(StartTimeKey) AS StartTimeKey, MIN(EndTimeKey) AS EndTimeKey, ENDROW, MIN(STARTROW) AS STARTROW, MAX(DURATION) AS DURATION, LOCATION, STAFF, SERVICELEVEL, MAX(ROOMBED) AS ROOMBED
			FROM E
			GROUP BY ENDROW, LOCATION, STAFF, SERVICELEVEL
		) AS ENDGROUP
		GROUP BY STARTROW, LOCATION, STAFF, SERVICELEVEL
	) AS A
	WHERE DURATION >= @IN
	Option(MaxRecursion 32767);


--SELECT * 
--FROM #ALLEVENTS E
--return

	SELECT MAX(ROOMBED) AS ROOMBED, COUNT(DISTINCT StartTimeKey) NUMOFSTAFF, MAX([HourOfDayAMPM])+' '+MAX([AMPM]) AS HOURS, HourOfDayMilitary
	FROM [dbo].[DimTime] T
	LEFT JOIN #ALLEVENTS E ON E.StartTimeKey = T.TimeKey
	GROUP BY LOCATION, HourOfDayMilitary
	HAVING HourOfDayMilitary >= 0
	ORDER BY 1, HourOfDayMilitary

	DROP TABLE #LOCATION
	DROP TABLE #EVENTS
	DROP TABLE #ALLEVENTS
END
GO


