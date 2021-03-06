Flux
====

Flux is a database that: 

* Accepts input in the form of structured events.
* Computes data joins at write time via static event transformations.
* Exposes a flat keyspace for querying ordered sets of values and counts of values.

Some motivating examples:

* Rolled-up counts for analytics: an event like a pageview needs to be translated into a series of counter increments, 
so viewing Andy Warhol's artist page might trigger an increment of the counters "artist:pageviews:andy-warhol:2012-08-08:US-NY", 
"artist:pageviews:andy-warhol:2012-08:US-NY", "artist:pageviews:andy-warhol:2012:US-NY", "artist:pageviews", etc. 
Each of these counters can be queried invididually.

* Pre-computing a join that's too expensive to run at query time: a user's feed can be represented as a join between the 
list of users they follow and the list of posts by each of those users, sorted by the time of the post. Instead of running
the join at query time in Flux, the 'post' event is instead translated into multiple writes onto the feeds of all followers 
of the posting user, which makes querying a feed a very fast operation.

More information
================

* [Getting Started](flux/tree/master/doc/GettingStarted.md)
* [Running Tests](flux/tree/master/doc/RunningTests.md)
* [MaQuery Language](flux/tree/master/doc/MQL.md)
* [API] (flux/tree/master/doc/API.md)