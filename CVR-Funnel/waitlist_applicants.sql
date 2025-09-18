--- all waitlist applicants
with old_tof as (
select distinct unique_link
from segment_events_raw.driver_production.workflow_step_rendered
where 1=1
  and page_id = 'TOF_WAITLIST_PAGE'
)

, old_bof as ( -- Launched June 2024
select distinct unique_link
from segment_events_raw.driver_production.workflow_step_rendered
where 1=1
  and page_id = 'BACKGROUND_CHECK'
  and coalesce(is_in_bgc_waitlist_blocker_experiment, false) = true
)
  --- NEW WAITLIST ---  
, hard_block_render_tof as (
select distinct unique_link
from segment_events_raw.driver_production.workflow_step_rendered
where 1=1
  and page_id = 'WAITLIST_HARD_BLOCK_PAGE'
  and waitlist_step = 'DASHER_WAITLIST_STEP_AFTER_VEHICLE'
)

, hard_block_render_bof as (
select distinct unique_link
from segment_events_raw.driver_production.workflow_step_rendered
where 1=1
  and page_id = 'WAITLIST_HARD_BLOCK_PAGE'
  and waitlist_step = 'DASHER_WAITLIST_STEP_BEFORE_BGC'
)

-- Reserved  
, reserved_render_tof as (
select distinct unique_link
from segment_events_raw.driver_production.workflow_step_rendered
where 1=1
  and page_id = 'WAITLIST_LIMITED_PAGE'
  and waitlist_step = 'DASHER_WAITLIST_STEP_AFTER_VEHICLE'
)

, reserved_render_bof as (
select distinct unique_link
from segment_events_raw.driver_production.workflow_step_rendered
where 1=1
  and page_id = 'WAITLIST_LIMITED_PAGE'
  and waitlist_step = 'DASHER_WAITLIST_STEP_BEFORE_BGC'
)


select 
  dda.applied_date
  , case
      when old_tof.unique_link is not null
      or old_bof.unique_link is not null
      or hbtof.unique_link is not null
      or hbbof.unique_link is not null
      or rtof.unique_link is not null
      or rbof.unique_link is not null then 'Hit Waitlist'
      else 'No Waitlist'
    end as all_waitlist_flag
  , count(distinct dasher_applicant_id) applicants_cnt
from edw.dasher.dimension_dasher_applicants dda
-- Old WL
left join old_tof on old_tof.unique_link = dda.unique_link
left join old_bof on old_bof.unique_link = dda.unique_link
-- New WL 
left join hard_block_render_tof hbtof on hbtof.unique_link = dda.unique_link
left join hard_block_render_bof hbbof on hbbof.unique_link = dda.unique_link
left join reserved_render_tof rtof on rtof.unique_link = dda.unique_link
left join reserved_render_bof rbof on rbof.unique_link = dda.unique_link
where 1=1
  and dda.applied_date between '2025-09-01' and current_date
group by all
