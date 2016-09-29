select s.Summary_ID, Event_Time,  Location_Key, f.In_Room_Duration, Activity_Type_Desc,Staff_Key, Service_Level_Key
 from (
select Summary_ID
  FROM [RMDW].[dbo].[FactEventActivity] f
 --  join DimDetailDesc d on d.Detail_Desc_Key = f.Detail_Desc_Key 
 where In_Room_Duration is not null and (Staff_Key > 0 or Service_Level_Key>0)
--    order by 1 desc
) as s
join FactEventActivity f on f.Summary_ID = s.Summary_ID
join DimDetailDesc d on d.Detail_Desc_Key = f.Detail_Desc_Key
order by Summary_ID, Event_Time

--374032,360349
select Location_Key,count(Summary_ID)
  FROM [RMDW].[dbo].[FactEventActivity] f
 --  join DimDetailDesc d on d.Detail_Desc_Key = f.Detail_Desc_Key 
 where In_Room_Duration is not null and (Staff_Key > 0 or Service_Level_Key>0)
 group by Location_Key
 having COUNT(summary_id) > 1


 select Location_Key, Event_Time, Staff_Key, dateadd(hh, In_Room_Duration, Event_Time) as endtime, f.Fact_Event_Activity_Key, Service_Level_Key
 --into #events
  FROM [RMDW].[dbo].[FactEventActivity] f
   --join DimDetailDesc d on d.Detail_Desc_Key = f.Detail_Desc_Key 
 where In_Room_Duration >2 and (Staff_Key > 0 )--or Service_Level_Key>0) --and Location_Key = 717
 --order by f.Location_Key

 select count(1), e.Location_Key --datediff(ss , e2.event_time, case when e.endtime > e2.endtime then e2.endtime else e.endtime end ), case when e.endtime > e2.endtime then e2.endtime else e.endtime end, e2.event_time, *--
 from #events e
 join #events e2 on e.Location_Key = e2.Location_Key and (e.Staff_Key <> e2.Staff_Key or e.Service_Level_Key<>e2.Service_Level_Key)
 and e2.Event_Time between e.Event_Time and e.endtime and datediff(hh , e2.event_time, case when e.endtime > e2.endtime then e2.endtime else e.endtime end ) >2
 --where e.Location_Key = 717
 group by e.Location_Key

 drop table #events