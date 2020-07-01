## This is an attempt to create a R version of the density calculator
## again, the distanced produced is the nearest as the bird flies, not
## by drive/walk time.
## A word on the libraries here, spatialrisk is rather gready on the 
## memory but as it runs on c# and does the heavy lifting I don't 
## have a quick alternative. I'm sure you could do this in other ways
## but this is attempting to do everything with the highest economy of 
## scale, not up front cost.

library(spatialrisk)
library(tidyverse)
library(censusxy)
library(stringr)


## this is a reduced copy of the voter file available in the Franklin 
## county Board of Elections Website. I choose it as a representation
## of the type of file one might be working with, and this is a 
## subset of about 100k records, again, just for purpose of size on 
## Github.

records <- read.csv('~/Downloads/voterfile_reduced.csv', header=TRUE)

## concatinate the address lines into something usable
records$RES_ADDRESS <- paste(records$RES_HOUSE," ",records$RES.STREET, sep = "")

records$address <- paste(records$RES_HOUSE," ",records$RES.STREET, ", ", 
                         records$RES_CITY, ", ",records$RES_STATE,", ", 
                         records$RES_ZIP, sep = "")

## segment to geocode the records, can be skipped down to the line 
## 'prep the results for use with spatialrisk'.
## note return = 'locations' returns only successful matches, 
## as a 
## return = 'geographies' will return all records. 
## added in timing and ran for 10k sample

geostart_time <- proc.time()

coded_records <- cxy_geocode(records[1:10000,], street = "RES_ADDRESS", 
                             city = "RES_CITY", state = "RES_STATE", 
                           output = "simple", class = "sf")

geoend_time <- proc.time() - geostart_time
print(c("geocoding time ", geoend_time))

### optional write out geocoded elements so we don't have to repeat
write.csv(coded_records, file="Geocoded_records.csv",row.names = FALSE)

## clean returned latlong
lnew<- coded_records$geometry%>%
  str_remove_all(., "[c(),]")%>%
  str_split_fixed(., " ", 2)%>%
  as.data.frame()
  
lnew <- rename(lnew, c("long"="V1", "lat"="V2"))
cols.num <- c("long","lat")
lnew[cols.num] <- sapply(lnew[cols.num],as.double)
bind <- cbind(coded_records,lnew)

## This function works by mapping across each row of the 
## bind table, and finding the nearest point within the 
## variable 'radius". note for here I've set it to 1000
## meters. You could expand or contract this, which would
## change the operating margins. note that the results, ans1
## are the nearest geographic neighhbor, in order which then
## needs to be joined back to the orginial table. the new 
## column distance_m is the distance between that value and the
## next dwelling in meters. 
## timing this just for fun. Start the clock!
start_time <- proc.time()
ans1 <- purrr::map2_dfr(bind$long, bind$lat,  
                ~spatialrisk::points_in_circle(bind, .x, .y, 
                                               lon = long, 
                                               radius = 1000)[2,])

# Stop the clock
end_time <- proc.time() - start_time
print(c('mapping distance time clocks: ',end_time[3]))

## at this point I've run this twice and it ends at about 30 minutes on my local machine
## for 10k records, which is rather unwieldly. That would requre something
## on order of three days if you were to attempt 
 
## rename the neighbor columns                                    
and2 <- ans1

## join the original table to the new neighbor table
                        
result <- cbind(bind, ans1)
head(result)


## experimenting with a split/apply combine approach
## this has essentially the same process but is vastly faster.
## the obvious downside is that instead of finding what is
## the true closest observation it has an artificial boudary
## around the precinct, and could miss a house on the same 
## street due to that. I think this could be an acceptable
## sacrifice in asmuch as most people cut turf on those 
## boundaries anyway, and therefore this is in line with application
## this version runs in about 10 minutes, so a third of the time cost.

splittime <- proc.time()

biny <- as.data.frame(bind)


out <- bind %>%
  group_split(PRECINCT) %>%
  map(~ {
    dat <- .x
    purrr::map2_dfr(dat$long, dat$lat,             
                    ~spatialrisk::points_in_circle(dat, .x, .y, 
                                                   lon = long, 
                                                   radius = 1000)[2,])
  })%>%
  purrr::map_df(., ~.x)

splitend_time <- proc.time() - splittime

print(c('mapping distance time clocks: ',splitend_time[3]))

## both of these are the same, 'out' being for the fast/easy method
## and 'result' being the larger table. pick whichever 
outresult <- cbind(bind, out)
outresult %>%
  group_by(PRECINCT) %>%
  summarise(across(distance_m, mean, na.rm = TRUE), across(COUNTY.ID, n_distinct))%>%
  rename("mean_distance"=distance_m)%>%
  rename("DistinctIDs"=COUNTY.ID)%>%
  as.data.frame()%>%
  select("PRECINCT","mean_distance", "DistinctIDs")%>%
  .[order(.$mean_distance),]-> grouped_precincts_sumed

grouped_precincts_sumed

## summarize and standardize the the results for the export
## note the naming conventions should be changed to match your file

result %>%
  group_by(PRECINCT) %>%
  summarise(across(distance_m, mean, na.rm = TRUE), across(COUNTY.ID, n_distinct))%>%
  rename("mean_distance"=distance_m)%>%
  rename("DistinctIDs"=COUNTY.ID)%>%select("PRECINCT","mean_distance", "DistinctIDs") -> precincts_summarized

precincts_summarized <- as.data.frame(precincts_summarized)
precincts_summarized <- select(precincts_summarized,c("PRECINCT","mean_distance", "Distinct IDs"))
precincts_summarized <- precincts_summarized[order(precincts_summarized$mean_distance),]

## export result, 'grouped_precincts_sumed' if you followed the fast route
## 'precincts_summarized' if you followed the global route

write.csv(precincts_summarized, file="rCalculatedDist.csv",row.names = FALSE)
