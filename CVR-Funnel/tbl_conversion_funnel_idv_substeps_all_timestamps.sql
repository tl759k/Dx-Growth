-- IDV substep tracking since 7/16: 
-- https://docs.google.com/spreadsheets/d/1LN97mMG0XfVglM3d3hmt1x6yBuhJaRGtpKMI7kxl1LU/edit?gid=1833335858#gid=1833335858
-- reference_id = unique_link
-- template_id: differentiates if it's onboarding idv or re-idv or others
-- event type: detailed steps
-- timestamp: created_at
-- set onboarding_template_id = [];

create or replace table proddb.static.tbl_conversion_funnel_idv_substeps_all_timestamps as 

-- S1: Inquiry Created
with tbl_inquiry_created as (
select
  reference_id as unique_link -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as inquiry_created
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'inquiry.created'
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_document_created as (
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as document_created
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'document.created'
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_document_submitted as (
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as document_submitted
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'document.submitted'
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_document_processed as (
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as document_processed
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'document.processed'
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_document_pending as (
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as document_pending
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'document.pending'
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_selfie_created as (
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as selfie_created
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'selfie.created'
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_selfie_submitted as (
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as selfie_submitted
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'selfie.submitted'
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_selfie_processed as (
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as selfie_processed
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'selfie.processed'
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_selfie_errored as (
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as selfie_errored
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'selfie.errored'
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_inquiry_failed as ( -- submission unsuccessful
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as inquiry_failed 
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'inquiry.failed' 
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_inquiry_expired as ( -- submission timed out
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as inquiry_expired 
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'inquiry.expired' 
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_inquiry_completed as ( -- submission successful
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as inquiry_completed
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'inquiry.completed' 
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_inquiry_marked_for_review as (
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as inquiry_marked_for_review
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'inquiry.marked-for-review' 
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_inquiry_approved as ( -- idv approve
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as inquiry_approved
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'inquiry.approved' 
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_inquiry_declined as ( -- idv decline
select
  reference_id as unique_link  -- unique_link
  , convert_timezone('UTC', 'America/Los_Angeles', min(created_at)) as inquiry_declined
from iguazu.driver.persona_inquiry_event_ice
where event_type = 'inquiry.declined' 
  -- and template_id in () -- get this from Jainalton. 
group by all
)

, tbl_device_type_from_vt as (-- find device type from vehicle submit step
select
  unique_link 
  , max_by(context_os_name, timestamp) context_os_name_last
  , min_by(context_os_name, timestamp) context_os_name_first
  , max_by(context_app_version, timestamp) context_app_version_last
  , min_by(context_app_version, timestamp) context_app_version_first  
from 
  segment_events_raw.driver_production.workflow_step_submit_success 
where 1=1
  and page_id = 'VEHICLE_DETAILS_PAGE'
  and context_os_name is not null
group by all
)

select
  dda.dasher_applicant_id
  , dda.dasher_id
  , dda.unique_link
  , dda.applied_date -- generated after phone and email, dasher_applicant_id and user_id are created, before profile submit
  , dda.first_dash_date
  , case 
      when vt_dt.context_os_name_first is null and vt_dt.context_os_name_last is null then null
      when vt_dt.context_os_name_first = 'iOS' or vt_dt.context_os_name_last = 'iOS' then 'iOS'
      when vt_dt.context_os_name_first = 'Android' and vt_dt.context_os_name_last = 'Android' then 'Android'
      else concat(vt_dt.context_os_name_first, '-' , vt_dt.context_os_name_last)
     end as device_type  
  , case 
      when vt_dt.context_app_version_first = vt_dt.context_app_version_last then vt_dt.context_app_version_last
      else concat(vt_dt.context_app_version_first, '-' , vt_dt.context_app_version_last)
     end as app_version
  , icr.inquiry_created
  , dc.document_created
  , ds.document_submitted
  , dpr.document_processed
  , dpe.document_pending
  , sc.selfie_created
  , ss.selfie_submitted
  , sp.selfie_processed
  , se.selfie_errored
  , inf.inquiry_failed
  , ie.inquiry_expired
  , icp.inquiry_completed
  , imr.inquiry_marked_for_review
  , ia.inquiry_approved
  , id.inquiry_declined
from edw.dasher.dimension_dasher_applicants dda 
left join tbl_device_type_from_vt vt_dt on vt_dt.unique_link = dda.unique_link
left join tbl_inquiry_created icr on icr.unique_link = dda.unique_link
left join tbl_document_created dc on dc.unique_link = dda.unique_link
left join tbl_document_submitted ds on ds.unique_link = dda.unique_link
left join tbl_document_processed dpr on dpr.unique_link = dda.unique_link
left join tbl_document_pending dpe on dpe.unique_link = dda.unique_link
left join tbl_selfie_created sc on sc.unique_link = dda.unique_link
left join tbl_selfie_submitted ss on ss.unique_link = dda.unique_link
left join tbl_selfie_processed sp on sp.unique_link = dda.unique_link
left join tbl_selfie_errored se on se.unique_link = dda.unique_link
left join tbl_inquiry_failed inf on inf.unique_link = dda.unique_link
left join tbl_inquiry_expired ie on ie.unique_link = dda.unique_link
left join tbl_inquiry_completed icp on icp.unique_link = dda.unique_link
left join tbl_inquiry_marked_for_review imr on imr.unique_link = dda.unique_link
left join tbl_inquiry_approved ia on ia.unique_link = dda.unique_link
left join tbl_inquiry_declined id on id.unique_link = dda.unique_link
where icr.inquiry_created is not null
;

grant select on proddb.static.tbl_conversion_funnel_idv_substeps_all_timestamps to public
;


