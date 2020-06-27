# Density Calculators

These are a series of density calculators based on a precinct level, but would essentially work with only slight modifications for larger geographies. 
Note all calcuations are based on creating a haversine distance between one point and the next nearest, then averaging the distance between points and the next nearest neighbor. 

The PostgreSQL table was added first,  it's written based on a current instance that I've stood up but could be 
run on any table with precinct name, latitude and longitude. Please read the comments in that code block for detailed use cases and modifications. 
