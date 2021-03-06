USE [RMDW]
GO

IF OBJECT_ID('tempdb..#LOCATION') IS NOT NULL
    DROP TABLE #LOCATION
IF OBJECT_ID('tempdb..#EVENTS') IS NOT NULL
 DROP TABLE #EVENTS
IF OBJECT_ID('tempdb..#ALLEVENTS') IS NOT NULL
 DROP TABLE #ALLEVENTS
 IF OBJECT_ID('tempdb..#STAFF') IS NOT NULL
 DROP TABLE #STAFF

declare @date		DATETIME
DECLARE @startTime DATETIME
DECLARE @endTime DATETIME
declare @unit		NVARCHAR(50)
declare @levels	NVARCHAR(50)

set @date		='2013-11-20 23:59:01.000'
set	@unit		= 'Test'
set	@levels = 'RN, PCT, LPN'
	SET @startTime ='15:00:00'
	SET @endTime = '16:00:00'

	DECLARE @FACILITY INT
	SET @FACILITY =5

	DECLARE @OUT INT
	SET @OUT = 20

	DECLARE @IN INT
	SET @IN = 1

	DECLARE @OVERLAP INT
	SET @OVERLAP = 30

	DECLARE @StartDateTime DATETIME
	DECLARE	@EndDateTime   DATETIME

	SET @StartDateTime  = Convert(datetime,CONVERT(VARCHAR(8), @date, 1)+' '+@startTime)
	SET @EndDateTime = Convert(datetime,CONVERT(VARCHAR(8), @date, 1)+' '+@endTime)

	--DECLARE @StartTimeKey INT
	--DECLARE @EndTimeKey INT
	--SELECT @StartTimeKey = TimeKey FROM [dbo].[DimTime] WHERE TimeOfDayMilitary = @startTime
	--SELECT @EndTimeKey = TimeKey FROM [dbo].[DimTime] WHERE TimeOfDayMilitary = @endTime

	--SELECT @StartDateTime, @EndDateTime, @StartTimeKey,@EndTimeKey

	SELECT DISTINCT L.Location_Key, L.Room_Name+'-'+L.Bed_Name AS RoomBed
	INTO #LOCATION
	FROM [dbo].[DimZone] Z 
	JOIN [dbo].[DimZoneLocation] ZL ON ZL.Zone_Key = Z.Zone_Key AND ZL.Activate_Date < @EndDateTime AND ZL.Inactivate_Date >= @StartDateTime
	JOIN [dbo].[DimLocation] L ON L.Location_Key = ZL.Location_Key AND L.Activate_Date < @EndDateTime AND L.Inactivate_Date >= @StartDateTime
	WHERE Z.Zone_Name = LTRIM(RTRIM(@unit)) AND Z.Activate_Date < @EndDateTime AND Z.Inactivate_Date >= @StartDateTime
	AND Z.Facility_Key = @FACILITY AND L.Bed_ID > 0 AND L.Bed_Name <> '0' AND (CAST(L.Bed_Name AS INT) < 100 OR CAST(L.Bed_Name AS INT) > 199)

SELECT * FROM #LOCATION
--RETURN

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
	JOIN [dbo].[DimServiceLevel] SL ON SL.Service_Level_Name = LTRIM(RTRIM(L.Level_Name)) AND SL.RowStartDate <@EndDateTime AND SL.RowEndDate >= @StartDateTime
	JOIN [dbo].[DimStaffServiceLevel] SSL ON SSL.Service_Level_Key = SL.Service_Level_Key AND SSL.Activate_Date < @EndDateTime AND SSL.Inactivate_Date >= @StartDateTime
	WHERE SL.Facility_Key = @FACILITY AND SSL.Staff_Key > 0

 SELECT * FROM #STAFF
 --RETURN

 -- GET EVENTS
	SELECT F.Location_Key, RoomBed, F.Staff_Key, F.Service_Level_Key, Group_Time_Key as StartTimeKey, Group_Time_Key - In_Room_Duration as EndTimeKey, In_Room_Duration, Event_Time
	,ROW_NUMBER() OVER (PARTITION BY F.Location_Key, F.Staff_Key order by Group_Time_Key DESC) AS ROW, Fact_Event_Activity_Key
	INTO #EVENTS
	FROM [dbo].[FactEventActivity] F
	JOIN #LOCATION L ON F.Location_Key = L.Location_Key
	JOIN #STAFF S ON F.Staff_Key = S.Staff_Key
	WHERE F.Event_Time BETWEEN @StartDateTime AND @EndDateTime
	AND In_Room_Duration > 0 AND Group_Complete_Indr = 1

SELECT * FROM #EVENTS
--return
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
	SELECT StartTimeKey, LOCATION, ROOMBED, EndTimeKey, STAFF, DURATION
	INTO #ALLEVENTS
	FROM 
	(
		SELECT MAX(StartTimeKey) AS StartTimeKey, MAX(DURATION) DURATION, MAX(ROOMBED) AS ROOMBED, LOCATION, MIN(EndTimeKey) AS EndTimeKey, STAFF

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


SELECT T.TimeOfDayMilitary, ET.TimeOfDayMilitary, STAFF, DURATION
FROM #ALLEVENTS E
JOIN DimTime T ON T.TimeKey = E.StartTimeKey
JOIN DimTime ET ON ET.TimeKey = E.EndTimeKey
ORDER BY StartTimeKey DESC
--return

	SELECT MAX(ROOMBED) AS ROOMBED, COUNT(DISTINCT StartTimeKey) NUMOFSTAFF, MAX([HourOfDayAMPM])+' '+MAX([AMPM]) AS HOURS, HourOfDayMilitary
	FROM [dbo].[DimTime] T
	LEFT JOIN #ALLEVENTS E ON E.StartTimeKey = T.TimeKey
	GROUP BY LOCATION, HourOfDayMilitary
	HAVING HourOfDayMilitary >= 0
	ORDER BY 1, HourOfDayMilitary
GO


