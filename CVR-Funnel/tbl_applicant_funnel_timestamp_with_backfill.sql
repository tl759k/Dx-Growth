create or replace table static.tbl_applicant_funnel_timestamp_with_backfill as

with persona_status as ( 
select 
 reference_id as unique_link
 , min_by(status,updated_at) as min_status
 , min(updated_at) as min_updated_at
 , min(case when status = 'approved' then updated_at end) as first_approved_at
 , min(case when status = 'declined' then updated_at end) as first_declined_at
 , max_by(status,updated_at) as max_status
 , max(updated_at) as max_updated_at
from RISK_DATA_PLATFORM_PROD.PUBLIC.PERSONA_INQUIRY 
where 1=1
    and template_id in ('tmpl_kfaFkGugqG9jqh6aAuc21Vwd'
                        , 'tmpl_dos19dD2bQ9wjrnVjAWRo1Ff'
                        , 'itmpl_XSPKhqhr8JrQkR9xGffNqbiD3DzN'
                        , 'itmpl_Ryrwhboy242TPqhtDFKuYKZskkuz'
                        , 'itmpl_U8gkVX5Z5YSULpkiZhwzuBABY1w2' -- New template from IDV Native Launch Apr. 2025
                        , 'itmpl_gTxrLPpupfjHj8K9MdYFYwbrZHV2') -- New template from IDV Native Launch Apr. 2025
group by 1 
)

, tbl_profile_submit as (
select 
  user_id as unique_link -- unique_link 
  , convert_timezone('UTC', 'America/Los_Angeles', min(timestamp)) as profile_submit 
from 
  segment_events_raw.driver_production.DA_submit_profile 
group by 1
)

, tbl_vehicle_type_submit as (
select
  unique_link 
  , convert_timezone('UTC', 'America/Los_Angeles', min(timestamp)) as vehicle_type_submit 
from segment_events_raw.driver_production.workflow_step_submit_success 
where 1=1
  and page_id = 'VEHICLE_DETAILS_PAGE'
group by 1 
)

, tbl_idv_render as (
select 
  unique_link 
  , convert_timezone('UTC', 'America/Los_Angeles', min(timestamp)) as idv_render 
from 
  segment_events_raw.driver_production.workflow_step_rendered 
where 1=1
  and page_id = 'IDENTITY_VERIFICATION_LANDING_PAGE'
group by 1
)

, tbl_idv_start as (
select 
  user_id as unique_link -- unique_link 
  , convert_timezone('UTC', 'America/Los_Angeles', min(timestamp)) as idv_start 
from 
  segment_events_raw.driver_production.DA_track_idv_steps 
where 1=1
  and name = 'start'
group by 1
)

, tbl_idv_submit as (
select 
  coalesce(unique_link, reference_id, user_id) as unique_link -- unique_link 
  , convert_timezone('UTC', 'America/Los_Angeles', min(timestamp)) as idv_submit 
from 
  segment_events_raw.driver_production.DA_track_idv_steps 
where 1=1
  and name = 'complete'
group by 1
)

, tbl_bgc_form_rendered as (
select 
  unique_link 
  , convert_timezone('UTC', 'America/Los_Angeles', min(timestamp)) as bgc_form_rendered 
from 
  segment_events_raw.driver_production.workflow_step_rendered 
where 1=1
  and page_id = 'BACKGROUND_CHECK'
group by 1
)

, tbl_bgc_submit as (
select 
  unique_link 
  , convert_timezone('UTC', 'America/Los_Angeles', min(timestamp)) as bgc_submit 
from 
  segment_events_raw.driver_production.workflow_step_submit_success 
where 1=1
  and page_id = 'BACKGROUND_CHECK'
group by 1
)

, tbl_account_activation as (
select 
  unique_link 
  , convert_timezone('UTC', 'America/Los_Angeles', min(timestamp)) as account_activation 
from 
  segment_events_raw.driver_production.dasher_activated_time 
group by 1
)

, all_steps_timestamps as (
select
  dda.dasher_applicant_id
  , dda.unique_link
  , dda.applied_date -- generated after phone and email, dasher_applicant_id and user_id are created, before profile submit
  , ps.profile_submit 
  , vt.vehicle_type_submit
  , idvr.idv_render 
  , idvst.idv_start
  , idvsu.idv_submit
  , pers.max_updated_at as idv_approve
  , bgcr.bgc_form_rendered
  , bgcs.bgc_submit
  , aa.account_activation
  , dda.first_dash_date
from edw.dasher.dimension_dasher_applicants dda 
left join tbl_profile_submit ps on ps.unique_link = dda.unique_link
left join tbl_vehicle_type_submit vt on vt.unique_link = dda.unique_link
left join tbl_idv_render idvr on idvr.unique_link = dda.unique_link
left join tbl_idv_start idvst on idvst.unique_link = dda.unique_link
left join tbl_idv_submit idvsu on idvsu.unique_link = dda.unique_link
left join persona_status pers on pers.unique_link = dda.unique_link and pers.max_status = 'approved'
left join tbl_bgc_form_rendered bgcr on bgcr.unique_link = dda.unique_link
left join tbl_bgc_submit bgcs on bgcs.unique_link = dda.unique_link
left join tbl_account_activation aa on aa.unique_link = dda.unique_link
where 1=1 
group by all
)

-- avg time between applied date and profile submit
, apply_to_profile_submit as (
select
  datediff('min', applied_date, profile_submit) time_delta
from all_steps_timestamps
where applied_date is not null and profile_submit is not null
  and time_delta between 0 and 2000
  and applied_date >= '2024-01-01'
)

, profile_submit_to_vehicle_type_submit as (
select
 datediff('min', profile_submit , vehicle_type_submit) time_delta
from all_steps_timestamps
where profile_submit is not null and vehicle_type_submit is not null
  and time_delta between 0 and 600
  and applied_date >= '2024-01-01'
)

, vehicle_type_submit_to_idv_render as (
select
 datediff('min', vehicle_type_submit, idv_render) time_delta
from all_steps_timestamps
where vehicle_type_submit is not null and idv_render is not null
  and time_delta between 0 and 600
  and applied_date >= '2024-01-01'
)

, idv_render_to_idv_start as (
select
  datediff('min', idv_render, idv_start) time_delta
from all_steps_timestamps
where idv_render is not null and idv_start is not null
  and time_delta between 0 and 600
  and applied_date >= '2024-01-01'
)

, idv_start_to_idv_submit as (
select
  datediff('min', idv_start, idv_submit) time_delta
from all_steps_timestamps
where idv_start is not null and idv_submit is not null
  and time_delta between 0 and 600
  and applied_date >= '2024-01-01'
)

, idv_submit_to_idv_approve as (
select
  datediff('min', idv_submit, idv_approve) time_delta
from all_steps_timestamps
where idv_submit is not null and idv_approve is not null
  and time_delta between 0 and 600
  and applied_date >= '2024-01-01'
)

, idv_approve_to_bgc_form_rendered as (
select
  datediff('min', idv_submit, bgc_form_rendered) time_delta
from all_steps_timestamps
where bgc_form_rendered is not null and idv_submit is not null
  and time_delta between 0 and 600
  and applied_date >= '2024-01-01'
)

, bgc_form_rendered_to_bgc_submit as (
select
  datediff('min', bgc_form_rendered, bgc_submit) time_delta
from all_steps_timestamps
where bgc_submit is not null and bgc_form_rendered is not null
  and time_delta between 0 and 600
  and applied_date >= '2024-01-01'
)

, bgc_submit_to_account_acctivation as (
select
  datediff('min', bgc_submit, account_activation) time_delta
from all_steps_timestamps
where account_activation is not null and bgc_submit is not null
  and time_delta between 0 and 600
  and applied_date >= '2024-01-01'
)

, account_acctivation_to_first_dash as (
select
  datediff('min', account_activation, first_dash_date) time_delta
from all_steps_timestamps
where first_dash_date is not null and account_activation is not null
  and time_delta between 0 and 1000
  and applied_date >= '2024-01-01'
)

, avg_apply_to_profile_submit as (
select avg(time_delta) time_delta
from apply_to_profile_submit
)

, avg_profile_submit_to_vehicle_type_submit as (
select avg(time_delta) time_delta
from profile_submit_to_vehicle_type_submit
)

, avg_vehicle_type_submit_to_idv_render as (
select avg(time_delta) time_delta
from vehicle_type_submit_to_idv_render
)

, avg_idv_render_to_idv_start as (
select avg(time_delta) time_delta
from idv_render_to_idv_start
)

, avg_idv_start_to_idv_submit as (
select avg(time_delta) time_delta
from idv_start_to_idv_submit
)

, avg_idv_submit_to_idv_approve as (
select avg(time_delta) time_delta
from idv_submit_to_idv_approve
)

, avg_idv_approve_to_bgc_form_rendered as (
select avg(time_delta) time_delta
from idv_approve_to_bgc_form_rendered
)

, avg_bgc_form_rendered_to_bgc_submit as (
select avg(time_delta) time_delta
from bgc_form_rendered_to_bgc_submit
)

, avg_bgc_submit_to_account_acctivation as (
select avg(time_delta) time_delta
from bgc_submit_to_account_acctivation
)

, avg_account_acctivation_to_first_dash as (
select avg(time_delta) time_delta
from account_acctivation_to_first_dash
)


, backfill_time as (
select 
  atp.time_delta as apply_to_profile_submit
  , ptv.time_delta as profile_submit_to_vehicle_type_submit
  , vti.time_delta as vehicle_type_submit_to_idv_render
  , irtis.time_delta as idv_render_to_idv_start
  , iti.time_delta as idv_start_to_idv_submit
  , itia.time_delta as idv_submit_to_idv_approve
  , iatbr.time_delta as idv_approve_to_bgc_form_rendered
  , brtbs.time_delta as bgc_form_rendered_to_bgc_submit
  , bstaa.time_delta as bgc_submit_to_account_acctivation
  , aatfd.time_delta as account_acctivation_to_first_dash
from avg_apply_to_profile_submit atp
left join avg_profile_submit_to_vehicle_type_submit as ptv on 1=1
left join avg_vehicle_type_submit_to_idv_render as vti on 1=1
left join avg_idv_render_to_idv_start as irtis on 1=1
left join avg_idv_start_to_idv_submit as iti on 1=1
left join avg_idv_submit_to_idv_approve as itia on 1=1
left join avg_idv_approve_to_bgc_form_rendered as iatbr on 1=1
left join avg_bgc_form_rendered_to_bgc_submit as brtbs on 1=1
left join avg_bgc_submit_to_account_acctivation as bstaa on 1=1
left join avg_account_acctivation_to_first_dash as aatfd on 1=1
)


, backfill_account_activation as (
select 
  a.dasher_applicant_id
  , a.unique_link
  , a.applied_date as applied_date_raw
  , a.profile_submit as profile_submit_raw
  , a.vehicle_type_submit as vehicle_type_submit_raw
  , a.idv_render as idv_render_raw
  , a.idv_start as idv_start_raw
  , a.idv_submit as idv_submit_raw
  , a.idv_approve as idv_approve_raw
  , a.bgc_form_rendered as bgc_form_rendered_raw
  , a.bgc_submit as bgc_submit_raw
  , a.account_activation as account_activation_raw
  , a.first_dash_date
  , b.*
  , case when account_activation is null and first_dash_date is not null then dateadd('min',  -account_acctivation_to_first_dash, first_dash_date) 
      else account_activation end as account_activation
from all_steps_timestamps a
left join backfill_time b on 1=1
)

, backfill_bgc_submit as (
select 
  *
  , case when bgc_submit_raw is null and account_activation is not null then dateadd('min',  -bgc_submit_to_account_acctivation, account_activation) 
      else bgc_submit_raw end as bgc_submit
from backfill_account_activation
)

, backfill_bgc_form_rendered as (
select 
  *
  , case when bgc_form_rendered_raw is null and bgc_submit is not null then dateadd('min',  -bgc_form_rendered_to_bgc_submit, bgc_submit) 
        else bgc_form_rendered_raw end as bgc_form_rendered
from backfill_bgc_submit
)

, backfill_idv_approve as (
select 
  *
  , case when idv_approve_raw is null and bgc_form_rendered is not null then dateadd('min',  -idv_approve_to_bgc_form_rendered, bgc_form_rendered) 
        else idv_approve_raw end as idv_approve
from backfill_bgc_form_rendered
)


, backfill_idv_submit as (
select 
  *
  , case when idv_submit_raw is null and idv_approve is not null then dateadd('min',  -idv_submit_to_idv_approve, idv_approve) 
        else idv_submit_raw end as idv_submit
from backfill_idv_approve
)

, backfill_idv_start as (
select 
  *
  , case when idv_start_raw is null and idv_submit is not null then dateadd('min',  -idv_start_to_idv_submit, idv_submit) 
        else idv_start_raw end as idv_start
from backfill_idv_submit
)

, backfill_idv_render as (
select 
  *
  , case when idv_render_raw is null and idv_start is not null then dateadd('min',  - idv_render_to_idv_start, idv_start) 
        else idv_render_raw end as idv_render
from backfill_idv_start
)

, backfill_vehicle_type_submit as (
select 
  *
  , case when vehicle_type_submit_raw is null and idv_render is not null then dateadd('min',  -vehicle_type_submit_to_idv_render, idv_render) 
        else vehicle_type_submit_raw end as vehicle_type_submit
from backfill_idv_render
)

, backfill_profile_submit as (
select 
  *
  , case when profile_submit_raw is null and vehicle_type_submit is not null then dateadd('min',  -profile_submit_to_vehicle_type_submit, vehicle_type_submit) 
        else profile_submit_raw end as profile_submit
from backfill_vehicle_type_submit
)

, backfill_applied_date as (
select 
  *
  , case when applied_date_raw is null and profile_submit is not null then dateadd('min',  -apply_to_profile_submit, profile_submit) 
        else applied_date_raw end as applied_date
from backfill_profile_submit
)

, finnal_backfill as (
select
  dasher_applicant_id
  -- with backfill results
  , unique_link
  , applied_date
  , profile_submit
  , vehicle_type_submit
  , idv_render
  , idv_start
  , idv_submit
  , idv_approve
  , bgc_form_rendered
  , bgc_submit
  , account_activation
  , first_dash_date
  -- raw
  , applied_date_raw
  , profile_submit_raw
  , vehicle_type_submit_raw
  , idv_render_raw
  , idv_start_raw
  , idv_submit_raw
  , idv_approve_raw
  , bgc_form_rendered_raw
  , bgc_submit_raw
  , account_activation_raw
  , case 
      when (applied_date_raw is null and applied_date is not null)
        or (profile_submit_raw is null and profile_submit is not null)
        or (vehicle_type_submit_raw is null and vehicle_type_submit is not null)
        or (idv_render_raw is null and idv_render is not null)
        or (idv_start_raw is null and idv_start is not null)
        or (idv_submit_raw is null and idv_submit is not null)
        or (idv_approve_raw is null and idv_approve is not null)
        or (bgc_form_rendered_raw is null and bgc_form_rendered is not null)
        or (bgc_submit_raw is null and bgc_submit is not null)
        or (account_activation_raw is null and account_activation is not null)
      then 1 else 0 end as backfilled
from backfill_applied_date
)

select * from finnal_backfill
;
