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
print("geocoding took: ",geoend_time)

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
## 
## timing this just for fun. Start the clock!
start_time <- proc.time()
ans1 <- purrr::map2_dfr(bind$long, bind$lat,  
                ~spatialrisk::points_in_circle(bind, .x, .y, 
                                               lon = long, 
                                               radius = 1000)[2,])

# Stop the clock
end_time <- proc.time() - start_time
print(end_time)
 
                                              
colnames(ans1) <- c("closestid", "n.lat", "n.long", "n.precinctname", 
                     "n.address", "n.city", "n.state", "n.zip", "distance_m")
                        
result <- cbind(records, ans1)
result


result %>%
  group_by(PrecinctName) %>%
  summarise(across(distance_m, mean, na.rm = TRUE), across(VANID, n_distinct))%>%
  rename("mean_distance"=distance_m)%>%
  rename("Distinct VANID"=VANID) -> precincts_summarized



summarise(Unique_Elements = n_distinct(VANID))
summarise(MeanDist = mean(distance_m, na.rm=TRUE))
