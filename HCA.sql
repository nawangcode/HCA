USE [RMDW]
GO


declare @date		DATETIME
declare @unit		NVARCHAR(50)
declare @levels	NVARCHAR(50)

set @date		='2013-11-20 23:59:01.000'
set	@unit		= 'Test'
set	@levels = 'RN, PCT, LPN'

DECLARE @FACILITY INT
SET @FACILITY = 5

DECLARE @OUT INT
SET @OUT = 20

DECLARE @IN INT
SET @IN = 1--30
--SELECT CONVERT(VARCHAR(8), @date, 112) AS [YYYYMMDD]
--	SET @date = CONVERT(date, @date)
--	SELECT @date 
	--	GET LOCATION KEY
	Declare @unitFilter table(
		Unit_Name NVARCHAR(50)
	)
	;WITH UnitFilter(j,Unit_Name)	AS
	(
		SELECT	
		CHARINDEX(',', @unit+','),   
		SUBSTRING(@unit, 1, CHARINDEX(',',@unit+',')-1)
		UNION ALL
		SELECT	
		CHARINDEX(',', @unit+',', j+1),
		SUBSTRING(@unit, j+1, CHARINDEX(',',@unit+',',j+1)-(j+1))
		FROM	UnitFilter
		WHERE	CHARINDEX(',',@unit+',',j+1) <> 0
	)
	--SELECT * FROM UnitFilter
	--insert into @unitFilter
	SELECT DISTINCT L.Location_Key, L.Room_Name+'-'+L.Bed_Name AS RoomBed
	INTO #LOCATION
	FROM UnitFilter U
	JOIN [dbo].[DimZone] Z ON Z.Zone_Name = LTRIM(RTRIM(U.Unit_Name)) AND @date BETWEEN CAST(FLOOR(CAST(Z.Activate_Date AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(Z.Inactivate_Date AS FLOAT ) ) AS DATETIME )--@date >= Z.Activate_Date AND @date < Z.Inactivate_Date 
	JOIN [dbo].[DimZoneLocation] ZL ON ZL.Zone_Key = Z.Zone_Key AND @date BETWEEN CAST(FLOOR(CAST(ZL.Activate_Date AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(ZL.Inactivate_Date AS FLOAT ) ) AS DATETIME )
	JOIN [dbo].[DimLocation] L ON L.Location_Key = ZL.Location_Key AND @date BETWEEN CAST(FLOOR(CAST(L.Activate_Date AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(L.Inactivate_Date AS FLOAT ) ) AS DATETIME )
	WHERE Z.Facility_Key = @FACILITY AND L.Bed_ID > 0 AND L.Bed_Name <> '0' AND (CAST(L.Bed_Name AS INT) < 100 OR CAST(L.Bed_Name AS INT) > 199)

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

	SELECT DISTINCT SSL.Staff_Key
	INTO #STAFF
	FROM LevelFilter L
	JOIN [dbo].[DimServiceLevel] SL ON SL.Service_Level_Name = LTRIM(RTRIM(L.Level_Name)) AND @date BETWEEN CAST(FLOOR(CAST(SL.RowStartDate AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(SL.RowEndDate AS FLOAT ) ) AS DATETIME )
	JOIN [dbo].[DimStaffServiceLevel] SSL ON SSL.Service_Level_Key = SL.Service_Level_Key AND @date BETWEEN CAST(FLOOR(CAST(SSL.Activate_Date AS FLOAT ) ) AS DATETIME ) AND CAST(FLOOR(CAST(SSL.Inactivate_Date AS FLOAT ) ) AS DATETIME )
	WHERE SL.Facility_Key = @FACILITY AND SSL.Staff_Key > 0
 
 --SELECT * FROM #LOCATION
 --SELECT * FROM #STAFF
 --RETURN

 -- GET EVENTS
 SELECT TOP 4 F.Location_Key, RoomBed, F.Staff_Key, Group_Time_Key as StartTimeKey, Group_Time_Key - In_Room_Duration as EndTimeKey, In_Room_Duration, Event_Time
	,ROW_NUMBER() OVER (PARTITION BY F.Location_Key, F.Staff_Key order by Group_Time_Key DESC) AS ROW
 INTO #EVENTS
 FROM [dbo].[FactEventActivity] F
 JOIN #LOCATION L ON F.Location_Key = L.Location_Key
 JOIN #STAFF S ON F.Staff_Key = S.Staff_Key
WHERE F.Group_Date_Key = CONVERT(VARCHAR(8), @date, 112) AND In_Room_Duration > 0

SELECT * FROM #EVENTS
 
 ;WITH E(StartTimeKey, EndTimeKey, ENDROW, STARTROW, DURATION, LOCATION, STAFF)
AS
(
	SELECT StartTimeKey, EndTimeKey, ROW, ROW, In_Room_Duration, Location_Key, Staff_Key
	FROM #EVENTS
	UNION ALL
	SELECT E.StartTimeKey, D.EndTimeKey, D.ROW, IIF(E.STARTROW<E.ENDROW, E.STARTROW, E.ENDROW), D.In_Room_Duration+E.DURATION, Location_Key, Staff_Key
	FROM #EVENTS D
	JOIN E ON E.EndTimeKey - D.StartTimeKey < @OUT AND D.ROW = E.ENDROW + 1 AND E.LOCATION = D.Location_Key AND E.STAFF = D.Staff_Key
)

--SELECT * FROM E

SELECT MIN(StartTimeKey) AS StartTimeKey, MAX(DURATION) DURATION, MAX(EndTimeKey) EndTimeKey, MAX(ENDROW) ENDROW, STARTROW, LOCATION, STAFF
INTO #ALLEVENTS
FROM
(
	SELECT MIN(StartTimeKey) AS StartTimeKey, MAX(EndTimeKey) AS EndTimeKey, ENDROW, MIN(STARTROW) AS STARTROW, MAX(DURATION) AS DURATION, LOCATION, STAFF
	FROM E
	GROUP BY ENDROW, LOCATION, STAFF
) AS ENDGROUP
GROUP BY STARTROW, LOCATION, STAFF


SELECT * 
FROM #ALLEVENTS E
--JOIN [dbo].[DimTime] T ON T.TimeKey = E.StartTimeKey
--WHERE DURATION > @IN-- AND HourOfDayMilitary >= 0

--SELECT HourOfDayMilitary, COUNT(1)
--FROM
--(
SELECT HourOfDayMilitary, LOCATION, COUNT(DISTINCT StartTimeKey)
FROM [dbo].[DimTime] T
LEFT JOIN #ALLEVENTS E ON E.StartTimeKey = T.TimeKey
GROUP BY LOCATION, HourOfDayMilitary
HAVING HourOfDayMilitary >= 0
--) AS A 
--GROUP BY LOCATION, HourOfDayMilitary
ORDER BY 1

 DROP TABLE #LOCATION
 DROP TABLE #STAFF
 DROP TABLE #EVENTS
 DROP TABLE #ALLEVENTS