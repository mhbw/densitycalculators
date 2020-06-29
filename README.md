# Density Calculators

These are a series of density calculators based on a precinct level, but would essentially work with only slight modifications for larger geographies. 
Note all calcuations are based on creating a haversine distance between one point and the next nearest, then averaging the distance between points and the next nearest neighbor. 

The PostgreSQL table was added first,  it's written based on a current instance that I've stood up but could be 
run on any table with precinct name, latitude and longitude. Please read the comments in that code block for detailed use cases and modifications. 

The R script, densitycalculatR, has the benefit of including a geocoder, but is not as fast; in this instance it took ~27 minutes for 10k records. 

Further work in both cases might first household the addresses. in the case of the Franklin county records, for example, with so many shared dwellings it creates a vastly nearer distance.

The sample csv this was run on was from [the Franklin County Board of Elections](http://boelcd.franklincountyohio.gov)
