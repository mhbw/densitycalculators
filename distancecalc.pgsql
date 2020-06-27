--------------------------  POSTGRESQL DISTANCE CALCULATION AND AVEGAGE DISTANCE --------------------------

/** This code works on postgreSQL. it's written based on a current instance that I've stood up but could be 
run on any table with precinct name, latitude and longitude. This falls in six steps:

	1) the distance function 
	2) the test block of comparing what outputs would look like
	3) the averaging segment to calculate average distance in each segment
	4) the table creation line 
	5) inserting the averages into the table
	6) exporting the results into csv
	
Note that all of these beyond step 1 are optional. you could essentially do 1, 4, 5, and 6 and have a calculation 
exported. Secondly, this gives the nearest house by Haversine distance (as the crow flies) as opposed to
say something that would use mapped street distance. This means it likely becomes less precise in sparser
areas but would still accurately find where a place was in fact dense. 


modifications and notes welcome  **/


/** ** ** ** ** ** ** ** ** ** ** ** SECTION 1:  DISTANCE FUNCTION ** ** ** ** ** ** ** ** ** ** ** **/ 

/** heavy debt here to a segment I found from a website called GeoDataSource
NOTE: in order to return kilometers the units variable should be 'K', otherwise it defaults to miles 
e.g. SELECT linear_distance(<latitude of first point> , <longitude of first point> , 
<latitude of second point>,<longitude of second point>, 'K');
**/




CREATE OR REPLACE FUNCTION linear_distance(lat1 float, lon1 float, lat2 float, lon2 float, units varchar)
RETURNS float AS $dist$
    DECLARE
        dist float = 0;
        radlat1 float;
        radlat2 float;
        theta float;
        radtheta float;
    BEGIN
        IF lat1 = lat2 AND lon1 = lon2
            THEN RETURN dist;
        ELSE
            radlat1 = pi() * lat1 / 180;
            radlat2 = pi() * lat2 / 180;
            theta = lon1 - lon2;
            radtheta = pi() * theta / 180;
            dist = sin(radlat1) * sin(radlat2) + cos(radlat1) * cos(radlat2) * cos(radtheta);

            IF dist > 1 THEN dist = 1; END IF;

            dist = acos(dist);
            dist = dist * 180 / pi();
            dist = dist * 60 * 1.1515;

            IF units = 'K' THEN dist = dist * 1.609344; END IF;
            IF units = 'N' THEN dist = dist * 0.8684; END IF;

            RETURN dist;
        END IF;
    END;
$dist$ LANGUAGE plpgsql;


/** ** ** ** ** ** ** ** ** ** ** ** SECTION 2:  Test calculations ** ** ** ** ** ** ** ** ** ** ** **/ 

/** This table uses my geography table, subsets it to only rows with complete cases of lat/long, and then lags 
based on precinct to the next nearest latitude. 

problems/challenges: I fixed having the null value on the first row by having the table loop back around when 
the result is null, using LAG(, -1). That works great until the very last value, which then pulls the distance
of the row behind it. That's not a massive problem as it's consistant in all precincts but would slightly 
inflate the issue in rural counties where the last value could be far apart and therefore in effect square 
the error rate on what is potentially the largest value. At some point I'd like to find something 
that is slightly more elegant but in a single row I don't think it discounts things too much.

Second minor note, VANID is the primary key here, and should be swapped out for whatever the pkey is on
your table, as well as changing the schema/table itself
**/



SELECT *
	, linear_distance(latitude, longitude, modified_lag_lat, modified_lag_long, 'K') AS next_vanid_dist
FROM
(
SELECT vanid -- modify appropriately 
	, precinctname
	, latitude
	, longitude
	,CASE WHEN LAG(latitude,1) OVER (PARTITION BY precinctname order by  latitude desc) IS NULL 
		THEN LAG(latitude,-1) OVER (PARTITION BY precinctname order by  latitude desc)
		ELSE LAG(latitude,1) OVER (PARTITION BY precinctname order by  latitude desc) END AS modified_lag_lat
	, CASE WHEN LAG(latitude,1) OVER (PARTITION BY precinctname order by  latitude desc) IS NULL 
		THEN LAG(longitude,-1) OVER (PARTITION BY precinctname order by  latitude desc) 
		ELSE LAG(longitude,1) OVER (PARTITION BY precinctname order by  latitude desc) END AS modified_lag_long
FROM
	(
		SELECT * FROM
			gendata.geography  -- modify appropriately 
		WHERE latitude IS NOT NULL AND longitude IS NOT NULL
 		ORDER BY precinctname, latitude
 	) lin
) lin_laged
;

/** ** ** ** ** ** ** ** ** ** ** ** SECTION 3:  Test Average ** ** ** ** ** ** ** ** ** ** ** **/ 

/** this simply duplicates the above but spits out a sorted average of the precincts.
I multipled the average  1000 in order to get the count by meters.
same challenges as above on name spaces/schemas/tables
**/

SELECT 
	precinctname
	, count(distinct vanid) as distinct_voters
	, AVG(next_vanid_dist)*1000 as average_dist_k
FROM
(
	SELECT *
		, linear_distance(latitude, longitude, modified_lag_lat, modified_lag_long, 'K') AS next_vanid_dist
	FROM
		(
		SELECT vanid
			, precinctname
			, latitude
			, longitude
			,CASE WHEN LAG(latitude,1) OVER (PARTITION BY precinctname order by  latitude desc) IS NULL 
				THEN LAG(latitude,-1) OVER (PARTITION BY precinctname order by  latitude desc)
				ELSE LAG(latitude,1) OVER (PARTITION BY precinctname order by  latitude desc) END AS modified_lag_lat
			, CASE WHEN LAG(latitude,1) OVER (PARTITION BY precinctname order by  latitude desc) IS NULL 
				THEN LAG(longitude,-1) OVER (PARTITION BY precinctname order by  latitude desc) 
				ELSE LAG(longitude,1) OVER (PARTITION BY precinctname order by  latitude desc) END AS modified_lag_long
		FROM
			(
				SELECT * FROM
					gendata.geography
				WHERE latitude IS NOT NULL AND longitude IS NOT NULL
				ORDER BY precinctname, latitude
			) lin 
		) lin_laged
	) lindist_calcs
GROUP BY precinctname
ORDER BY average_dist_k ASC
;

/** ** ** ** ** ** ** ** ** ** ** ** SECTION 4:  Create Table ** ** ** ** ** ** ** ** ** ** ** **/ 
TRUNCATE TABLE IF EXISTS gendata.avg_precinct_distance;
CREATE TABLE gendata.avg_precinct_distance
	(
	precinctname varchar
	, distinct_voters int
	, average_dist_k float
	)
;

/** ** ** ** ** ** ** ** SECTION 5:  Insert Results into Table ** ** ** ** ** ** ** ** ** ** ** **/ 

INSERT INTO gendata.avg_precinct_distance
	(precinctname, distinct_voters, average_dist_k)
SELECT 
	precinctname
	, count(distinct vanid) as distinct_voters
	, AVG(next_vanid_dist)*1000 as average_dist_k
FROM
(
	SELECT *
		, linear_distance(latitude, longitude, modified_lag_lat, modified_lag_long, 'K') AS next_vanid_dist
	FROM
		(
		SELECT vanid
			, precinctname
			, latitude
			, longitude
			,CASE WHEN LAG(latitude,1) OVER (PARTITION BY precinctname order by  latitude desc) IS NULL 
				THEN LAG(latitude,-1) OVER (PARTITION BY precinctname order by  latitude desc)
				ELSE LAG(latitude,1) OVER (PARTITION BY precinctname order by  latitude desc) END AS modified_lag_lat
			, CASE WHEN LAG(latitude,1) OVER (PARTITION BY precinctname order by  latitude desc) IS NULL 
				THEN LAG(longitude,-1) OVER (PARTITION BY precinctname order by  latitude desc) 
				ELSE LAG(longitude,1) OVER (PARTITION BY precinctname order by  latitude desc) END AS modified_lag_long
		FROM
			(
				SELECT * FROM
					gendata.geography
				WHERE latitude IS NOT NULL AND longitude IS NOT NULL
				ORDER BY precinctname, latitude
			) lin 
		) lin_laged
	) lindist_calcs
GROUP BY precinctname
ORDER BY average_dist_k ASC
;


/** ** ** ** ** ** ** ** SECTION 6:  export to csv ** ** ** ** ** ** ** ** ** ** ** **/ 
-- this runs as selecting the results into csv but you could as well do it as a query directly
-- so for example if you don't have write access this would be handy

COPY gendata.avg_precinct_distance TO 'precinct_densisty.csv' DELIMITER ',' CSV HEADER;


/** if you don't have superuser this works as well in commandline psql

\copy gendata.avg_precinct_distance TO precinct_densisty.csv CSV HEADER DELIMITER ','

-- you might also consider limiting to only precincts with density above a certain number
-- 200 or less is considered urban, but you might do say urban and a count above 30 so there are 
-- at least 30 unique voters as well .that could work like so

\copy (select * from gendata.avg_precinct_distance where distinct_voters > 30 and average_dist_k <= 200) TO precinct_densisty.csv CSV HEADER DELIMITER ','






