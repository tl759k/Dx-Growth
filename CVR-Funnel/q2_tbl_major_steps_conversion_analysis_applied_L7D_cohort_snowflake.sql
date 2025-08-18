create or replace table proddb.static.tbl_major_steps_conversion_analysis_applied_L7D_cohort_snowflake as 

with week_dates as (
select distinct
  first_date_of_week_iso as week_start
  , last_date_of_week_iso as week_end
from edw.core.dimension_dates
where first_date_of_week_iso between '2024-01-01' and current_date
order by week_start desc
)

, good_or_bad_dashers as (
select distinct
  dasher_applicant_id
  , case 
      when is_deactivated_email = 1  then 'bad'
      when is_deactivated_phone = 1 then 'bad'      
      when is_deactivated_dl_token = 1 then 'bad'      
      when is_deactivated_ssn = 1 then 'bad'      
      when phone_count_applicants > 1 then 'bad' 
      when count_dash_ssn > 1 then 'bad'
      else 'good'
      end as good_or_bad_bucket
  , case
      when is_deactivated_email = 1  then 'bad'
      when is_deactivated_phone = 1 then 'bad'
      when is_deactivated_dl_token = 1 then 'bad'
      when is_deactivated_ssn = 1 then 'bad'
      when email_count_applicants>1 then 'bad' -- additional
      -- when VOIP_PHONE_INDICATOR = 1 then 'bad'
      when phone_count_applicants>1 then 'bad'
      when dl_count_dasher >1 then 'bad'  -- additional
      when count_dash_ssn >1 then 'bad'
      when COUNTRY_CONTINENT_NAME not in ('North America') then 'bad'  -- additional
      else 'good'
      end as good_or_bad_bucket_2
from sandhyasriraman.dasher_applicant_linkage_1
)

, phone_duplicates as ( 
select 
  phone_number
  , min(applied_date) as first_applied_date
  , count(distinct dasher_applicant_id) as dx_count
from edw.dasher.dimension_dasher_applicants 
where 1=1
group by 1
having dx_count > 1 
)


---========= Waitlist Applicants ========----------
--- all waitlist applicants
, old_tof as (
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

, waitlist_apps as (
select distinct
  case
    when old_tof.unique_link is not null
    or old_bof.unique_link is not null
    or hbtof.unique_link is not null
    or hbbof.unique_link is not null
    or rtof.unique_link is not null
    or rbof.unique_link is not null then 'Hit Waitlist'
    else 'No Waitlist'
  end as all_waitlist_flag
  , dasher_applicant_id
from edw.dasher.dimension_dasher_applicants dda
-- Old WL
left join old_tof on old_tof.unique_link = dda.unique_link
left join old_bof on old_bof.unique_link = dda.unique_link
-- New WL 
left join hard_block_render_tof hbtof on hbtof.unique_link = dda.unique_link
left join hard_block_render_bof hbbof on hbbof.unique_link = dda.unique_link
left join reserved_render_tof rtof on rtof.unique_link = dda.unique_link
left join reserved_render_bof rbof on rbof.unique_link = dda.unique_link
)

-----=========== End of WL Applicants ===========-------------------------------------


-- additional timestamps
, dash_now_access as (
select
  a.dasher_id
  , count(1) n_impressions
  , sum(a.is_dash_now) n_dash_now_impressions
  , div0(n_dash_now_impressions, n_impressions) dash_now_impression_rate
from proddb.public.fact_dasher_access_correctness a
inner join proddb.static.tbl_applicant_funnel_timestamp_with_backfill_snowflake b on a.dasher_id = b.dasher_id
       and date_trunc('week', a.active_date) = date_trunc('week', b.account_activation)
group by all
)

-- anyone who has an assignment
, tbl_assignment_creation_and_acceptance as (
select
  a.dasher_id
  , count(a.created_at) assignment_creation_cnt -- assignment_creation
  , avg(case when a.accepted_at is not null and a.unassigned_at is null then 1 else 0 end) as acceptance_rate
from proddb.prod_assignment.shift_delivery_assignment a
inner join proddb.static.tbl_applicant_funnel_timestamp_with_backfill_snowflake b on a.dasher_id = b.dasher_id
       and date_trunc('week', convert_timezone('UTC', 'America/Los_Angeles', a.created_at)) = date_trunc('week', b.account_activation) -- in activation week
group by all
)

, cohort_details as (
select
  week_start
  , case 
      when b.applied_date between week_start and week_end and (b.first_dash_date is null or b.first_dash_date >= week_start) then '1. Applied L7D' 
      when b.applied_date between dateadd('day', -30, week_start) and dateadd('day', -1, week_start) and (b.first_dash_date is null or b.first_dash_date >= week_start) then '2. Applied 7D-30D'
      when b.applied_date between dateadd('day', -180, week_start) and dateadd('day', -31, week_start) and (b.first_dash_date is null or b.first_dash_date >= week_start) then '3. Applied 30D-180D'
      when b.applied_date < dateadd('day', -180, week_start) and (b.first_dash_date is null or b.first_dash_date >= week_start)then '4. Applied 180D+' 
      when b.applied_date > week_end and (b.first_dash_date is null or b.first_dash_date >= week_start) then 'Applied After Measurement Period' 
      else 'Unmapped' end as cohort
  , dda.applied_country_id
  , dda.applied_country_name
  , dda.applied_submarket_id
  , dda.applied_submarket_name
  , case when dda.applied_submarket_id in (9723, 5037, 2543, 7185, 5038) then 'Yes' else 'No' end PR_flag
  , ifnull(d.good_or_bad_bucket, 'good')  good_or_bad_bucket
  , ifnull(d.good_or_bad_bucket_2, 'good') good_or_bad_bucket_2
  , case -- device type only becomes available for those dx apps who pass idv approve step
      when b.device_type like '%iOS%' then '1-iOS'
      when b.device_type like '%Android%' then '2-Android'
      else '3-Other'
    end as device_type
  , wla.all_waitlist_flag
  , case when (pd.phone_number is null -- No duplicate phone number
          or pd.first_applied_date = dda.applied_date) -- OR this is the first application from a phone number
      then 'Non-Dupe' else 'Dupe' end as phone_duplicate_flag
  , count(distinct b.dasher_applicant_id) as applicants
  --==== conversion steps ===-----
  -- , count(distinct case when account_activation is null or account_activation >= week_start then dasher_applicant_id end) as applicant_count_ex_activate
  , count(distinct case when b.profile_submit::date between week_start and week_end then b.dasher_applicant_id end) as profile_submit
  , count(distinct case when b.vehicle_type_submit::date between week_start and week_end then b.dasher_applicant_id end) as vehicle_submit
  , count(distinct case when b.idv_submit::date between week_start and week_end then b.dasher_applicant_id end) as idv_submit 
  , count(distinct case when convert_timezone('UTC', 'America/Los_Angeles', b.idv_approve)::date between week_start and week_end then b.dasher_applicant_id end) as idv_approve 
  , count(distinct case when b.bgc_submit::date between week_start and week_end then b.dasher_applicant_id end) as bgc_submit 
  , count(distinct case when b.account_activation::date between week_start and week_end then b.dasher_applicant_id end) as account_activation
  , count(distinct case when coalesce(b.first_impression_time, b.first_shift_creation)::date between week_start and week_end then b.dasher_applicant_id end) as first_impression_time
  , count(distinct case when coalesce(b.first_shift_creation, b.first_shift_check_in)::date between week_start and week_end then b.dasher_applicant_id end) as first_shift_creation
  , count(distinct case when coalesce(b.first_shift_check_in,b.first_dash_date)::date between week_start and week_end then b.dasher_applicant_id end) as first_shift_check_in
  , count(distinct case when b.account_activation::date between week_start and week_end and assignment_creation_cnt > 0 then b.dasher_applicant_id end) as has_assignment_creation
  , sum(case when b.account_activation::date between week_start and week_end then assignment_creation_cnt end) assignment_creation_cnt
  , sum(case when b.account_activation::date between week_start and week_end then assignment_creation_cnt * acceptance_rate end) assignment_accepted_cnt
  -- , avg(case when b.account_activation::date between week_start and week_end then acceptance_rate end) acceptance_rate
  , avg(case when b.account_activation::date between week_start and week_end then dash_now_impression_rate end) dash_now_access_rate
  , count(distinct case when b.first_dash_date between week_start and week_end then dda.dasher_id end) as first_delivery
  -- additional substeps of page render
  , count(distinct case when coalesce(b.vehicle_type_rendered,b.vehicle_type_submit)::date between week_start and week_end then b.dasher_applicant_id end) as vehicle_type_rendered
  , count(distinct case when coalesce(b.idv_render, b.idv_submit)::date between week_start and week_end then b.dasher_applicant_id end) as idv_render
  , count(distinct case when coalesce(b.bgc_form_rendered, b.bgc_submit)::date between week_start and week_end then b.dasher_applicant_id end) as bgc_form_rendered
  -- , idv_doc_select
  -- , idv_doc_capture
  -- , idv_selfie_select
  -- , idv_selfie_capture
  -- , idv_selfie_upload
from week_dates a
cross join proddb.static.tbl_applicant_funnel_timestamp_with_backfill_snowflake b 
left join waitlist_apps as wla on wla.dasher_applicant_id = b.dasher_applicant_id
left join edw.dasher.dimension_dasher_applicants dda on b.unique_link = dda.unique_link
left join good_or_bad_dashers d on d.dasher_applicant_id = b.dasher_applicant_id
left join phone_duplicates pd on pd.phone_number = dda.phone_number 
left join dash_now_access e on b.dasher_id = e.dasher_id
left join tbl_assignment_creation_and_acceptance f on b.dasher_id = f.dasher_id
where cohort = '1. Applied L7D'
group by all
order by 1 desc
)

select
  week_start
  , applied_country_id
  , applied_country_name
  , case 
      when applied_country_id = 1 and PR_flag = 'Yes' then 'US - Puerto Rico' 
      when applied_country_id = 1 and PR_flag = 'No' then 'US - Other Region' 
      else applied_country_name 
     end as country_region
  , cohort
  , all_waitlist_flag
  , device_type
  , good_or_bad_bucket
  , good_or_bad_bucket_2
  , applied_submarket_id
  , applied_submarket_name
  -- , PR_flag
  , phone_duplicate_flag
  -- , heatmap_busyness
  , sum(applicants) applicants
  , sum(profile_submit) profile_submit
  , sum(vehicle_type_rendered) vehicle_type_rendered
  , sum(vehicle_submit) vehicle_submit
  , sum(idv_render) idv_render
  , sum(idv_submit) idv_submit
  , sum(idv_approve) idv_approve
  , sum(bgc_form_rendered) bgc_form_rendered
  , sum(bgc_submit) bgc_submit
  , sum(account_activation) account_activation
  , sum(first_impression_time) first_impression_time
  , sum(first_shift_creation) first_shift_creation
  , sum(first_shift_check_in) first_shift_check_in
  , sum(has_assignment_creation) has_assignment_creation
  , sum(assignment_creation_cnt) assignment_creation_cnt
  , sum(assignment_accepted_cnt) assignment_accepted_cnt
  , div0(sum(assignment_accepted_cnt), sum(assignment_creation_cnt)) acceptance_rate
  , avg(dash_now_access_rate) dash_now_access_rate
  , sum(first_delivery) first_delivery
from cohort_details
group by all
order by 1 desc
;

grant select on proddb.static.tbl_major_steps_conversion_analysis_applied_L7D_cohort_snowflake  to public;
