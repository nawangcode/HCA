/****** Script for SelectTopNRows command from SSMS  ******/
--SELECT Z.Zone_Name, F.Group_Date_Key, Event_Time, F.*
--  FROM [RMDW].[dbo].[FactEventActivity] F
--  JOIN [dbo].[DimZoneLocation] DL ON DL.Location_Key  = F.Location_Key
--JOIN [dbo].[DimZone] Z ON Z.Zone_Key = DL.Zone_Key
--  WHERE Staff_Key > 0 AND F.Location_Key > 0 AND In_Room_Duration > 0

  SELECT top 4 *--Staff_Key, Location_Key, In_Room_Duration, Event_Time, dateadd(ss, In_Room_Duration, Event_Time) as endtime, Group_Time_Key AS STARTTIMEKEY, Group_Time_Key - In_Room_Duration AS ENDTIMEKEY
  ,ROW_NUMBER() OVER (order by f.Event_Time) AS ROW
  --into #event
  FROM [RMDW].[dbo].[FactEventActivity] F 
  --JOIN [dbo].[DimTime] T ON T.TimeKey = F.Group_Time_Key
  WHERE Staff_Key > 0 AND F.Location_Key > 0 AND In_Room_Duration > 0 and Group_Date_Key = '20131120'

  --where Summary_ID  =360318
  SELECT * FROM #event
  SELECT Event_Time, endtime, STARTTIMEKEY, ENDTIMEKEY, T.TimeOfDayMilitary, T1.TimeOfDayMilitary FROM #event
  JOIN [dbo].[DimTime] T ON T.TimeKey = STARTTIMEKEY
  JOIN [dbo].[DimTime] T1 ON T1.TimeKey = ENDTIMEKEY
--SELECT distinct HourOfDayMilitary, TimeOfDayMilitary, TimeKey
--  FROM [RMDW].[dbo].[DimTime] t
-- -- join #event e on e.Event_Time = t.TimeKey
--  where HourOfDayMilitary > 0 and TimeKey = '29662'
--  order by 1 
--SELECT E.In_Room_Duration, E1.In_Room_Duration, E.Event_Time, E1.Event_Time, E.In_Room_Duration + E1.In_Room_Duration AS DURATION
--FROM #event E
--JOIN #event E1 ON E1.Event_Time < dateadd(ss, 20, E.endtime) AND E1.ROW = E.ROW+1


;WITH E(EVENT_TIME, ENDTIME, ROW, ROW1)
AS
(
	SELECT Event_Time, ENDTIME, ROW, ROW--CAST(ROW AS INT), 0
	FROM #event
	UNION ALL
	SELECT E.Event_Time, A.endtime, A.ROW, IIF(E.ROW1<E.ROW, E.ROW1, E.ROW)--CASE WHEN E.ROW1 = 0 THEN E.ROW ELSE E.ROW1 END
	FROM #event A
	JOIN E ON A.Event_Time < dateadd(ss, 20, E.endtime) AND A.ROW = E.ROW + 1
)

SELECT * 
INTO #E1
FROM e

SELECT * FROM #E1

-- GROUP BY END TO GET MIN START, GROUP BY START TO GET MAX END
SELECT MIN(STARTTIME), MAX(ENDTIME), MAX(ROW), STARTROW
FROM
(
SELECT MIN(EVENT_TIME) AS STARTTIME, MAX(ENDTIME) AS ENDTIME, ROW, MIN(ROW1) AS STARTROW FROM #E1
GROUP BY ROW
) AS ENDGROUP
GROUP BY STARTROW


  
  DROP TABLE #event
  DROP TABLE #E1


  SELECT Convert(varchar,GETDATE(),108) 
  SELECT Convert(datetime,CONVERT(VARCHAR(8), GETDATE(), 1))

