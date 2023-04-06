################ District Density Calculator 4.0 ##################
## This project is a bigquery focused method of finding density in 
## a given geography. we're going to demonstrate a method of using 
## CTEs  to try and minimize weight and use BQ functions to find
## the most dense districts.
## This project used a private data set, but you should be able to 
## replicate in any occasion you have lat/long, districts, and unique IDs. 
## a better version would possibly have precincts and reg_address.
## There are style choices made along the way, please don't blindly 
## copy paste without reading the notes to be sure you know the
## interactions you're utilizing. Ideally, given these blocks
## this is a viable option for people to modify easily and have a 
## replicable product across campaigns. 

## We have a lot of cool geography tools added to bq so that's 
## a help. First we're going to make a much smaller table with 
## all viable targets (dems in this case) and then make a geometry
## using the st_geogpoint function which many be critical later
## this will be saved as geom
with voters as (
select voterbase_id
  , vb_vf_cd
  , vb_vf_county_name
  , vb_tsmart_latitude
  , vb_tsmart_longitude
  , vb_vf_reg_city
  , vb_vf_reg_zip
  , ST_GEOGPOINT(vb_tsmart_longitude, vb_tsmart_latitude) as geom
from `prod-generation-data-176bffe6.GA_targetsmart.voter_base`
where vb_vf_voter_status = "Active"
and vb_tsmart_partisan_score >= 50
and vb_tsmart_midterm_general_turnout_score >= 50),

## in order to prevent selecting people in the same household
## I'm going to create a feaux householding by only pulling the first registered 
## id. More optimally you could group by registered_address but we do not
## have access to that on this file. 
## BE AWARE OF WHAT THIS IS DOING: This will 'punish' apartment buildings
## for example. and will ignore the fact that you might consider density
## increased if you can get 3 people on one door. This calculation can
## only tell you where the next nearest voter is who is not in the same
## front door. Each campaign makes choices and you may choose to ignore the 
## household step. that's fine, but make those choices intentionally.
## in this case, this took the number of houses from ~56k to ~53k
## the average number of people in the homes were 1.05 so I will proceed
## with this choice as I do not think it will materially change the outcomes
households as (
  select   voterbase_id
  , vb_vf_cd
  , vb_vf_county_name
  , vb_tsmart_latitude
  , vb_tsmart_longitude
  , vb_vf_reg_city
  , vb_vf_reg_zip
  , ST_GEOGPOINT(vb_tsmart_longitude, vb_tsmart_latitude) as geom
FROM voters
QUALIFY DENSE_RANK () OVER (PARTITION BY TO_JSON_STRING(geom) ORDER BY voterbase_id DESC) = 1
),

## HERE BE DRAGONS: we're finding nearest with a self-join, which
## can get dicey, and costly, quickly. this is why it's best to 
## narrow as much as possible up top. If you have capacity, narrowing
## to one city, county, or sd would be wisest. Anything to limit.
## to that end, we will only consider places within 100 meters.
## ST_DWithin does that part. Note: here we are 'punishing'
## more rural voters. you may make a different choice here if you
## are working in a rural area, and widen the radius.
## one additional option; you could join on both geom and precinct
## or district to make this narrow if perhaps you've got a
## close district. generally it's optimal to have already narrowed
## to your target areas, so this is not a high priority.
nearest as (
SELECT a.voterbase_id
  , a.vb_vf_cd
  , a.vb_vf_county_name
  , a.vb_tsmart_latitude
  , a.vb_tsmart_longitude
  , a.vb_vf_reg_city
  , a.vb_vf_reg_zip
  , ST_DISTANCE(a.geom, b.geom, TRUE) as neighbor_distance
FROM households a JOIN households b
ON ST_DWithin(a.geom, b.geom, 1000) -- 100m search radius
group by 1, 2, 3, 4, 5,6,7,8
),

## drop the values that are further than 1000 or otherwise lack a 
## a viable neighbor. this again is a choice, some might 
## want to do another narrowing. but ST_DISTANCE will return a 0
## for the items that don't have a match, so an average would suddenly
## favor those items. We want to drop them. Again, this choice
## could also have consequences if you had a district with three
## voters, two super close and one far, but only counting the 
## super close and moving it up the rank. I suspect this is a very rare 
## possibility. Additionally, if someone is more than 1km away
## I believe you'd drop them anyway, so it's a fair calculation of
## the viable targets. In this case we dropped another 4k voters. I'd 
## say it's fair to expect that amount of fade anyway. One could also
## use this later to target phone calls to only uncanvassable locations. 
qualified as (
select voterbase_id
  , vb_vf_cd
  , vb_vf_county_name
  , vb_tsmart_latitude
  , vb_tsmart_longitude
  , vb_vf_reg_city
  , vb_vf_reg_zip
  , min(neighbor_distance) as nearest_neighbor
from nearest
where  neighbor_distance != 0.0
group by 1,2,3,4,5,6,7
),

## now we're at the nice easy part, finding
## average distance. This would create a real walkable
## density calc, e.g. how close is the next door 
## you can swap out vb_vf_county_name in order to 
## increase or decrease granularity. Ideally, Precinct or zip level
density as (
select vb_vf_county_name -- modify here to change the level of granularity
, AVG(nearest_neighbor) as avg_distance
from qualified
group by 1
)

## create reportable distance!
select * from density 
order by density.avg_distance asc
