The Flux API
============

Flux's API has one route for receiving events and a few routes for querying
values and counts.

The actual events accepted and values queryable depend on the Flux schema.
In what follows, we'll assume the following sample schema:

    // User following another user
    "client:gravity:action:follow": [{
      "targets": ["[followee].followers"],
      "add": "follower"
    }]

Events
======

To register an event with Flux, send an HTTP POST to `/events` with a body that consists of the JSON
string representing a list of pairs of event names and parameters. For example, to register the
event "client:gravity:action:follow:user" with parameters `{ follower: user:4ff448, followee: user:50000d }`,
you would post the body

    [['client:gravity:action:follow:user', { 'follower': 'user:4ff448', 'followee': 'user:50000d' }]]

to the URL `http://flux.art.sy/events`. This request will add "user:4ff448" to the set user:50000d:followers.

Multiple events can be sent in the same POST body. In the previous example, we could have sent two events
in the same body by POSTing something like the following:

    [['client:gravity:action:follow:user', { 'follower': 'user:4ff448', 'followee': 'user:50000d' }],
     ['client:gravity:action:follow:user', { 'follower': 'user:4ff449', 'followee': 'user:50000d' }]]

Flux queries return data in the reverse order in which Flux received the events. You can override this timestamp when 
sending an event by passing a time override (in seconds since
[the epoch](http://en.wikipedia.org/wiki/Epoch_\(reference_date\))) with the `@score` parameter by POSTing a body like this:

    [['client:gravity:action:follow:user', { 'follower': 'user:4ff448', 'followee': 'user:50000d', '@score': 1347487308 }]]

Obviously, there are no guarantees about the consistency of the server clock versus the clock
on the machine where you're sending events, but passing a time override like this is useful for
playing queued events or replaying events and having them show up in queries from Flux in
roughly the same order as they occurred.

Note that the argument to `@score` can be completely arbitrary; if the set to which you are sending events or storing values should be ordered by some parameter other than time (e.g., a game leaderboard), `@score` accepts any positive 31-bit integer argument.

The event API also allows setting MQL handlers at runtime by attaching them to the payload of a single event. 
A single handler can be specified by passing `@targets[]`, along with `@add` or `@remove`, and optionally `@maxStoredValues`. For example,
you could POST the following body to `http://flux.art.sy/events`:

    [['client:gravity:action:post', {'user': 'user1', 'post': 'post1', '@targets': '[user].followers.feedItems', '@add': 'post'}]]

Querying
========

Query the members of a set by calling `/query`, and passing the set's key in the `keys[]` parameter. For example, to query the followers of user:50000d, execute a HTTP GET against

    http://flux.art.sy/query?keys[]=user:50000d:followers

You can add a `maxResults` parameter to restrict the size of the result set. `maxResults`
defaults to 50 if it's omitted. If there are more than `maxResults` results, you'll get
an opaque cursor back in the `next` field of the results. To continue paging through
results, pass this cursor as the cursor parameter of the next call to same query. For
example,

    http://flux.art.sy/query?keys[]=user:50000d:followers&maxResults=1

might return

    { results: ['user:50000e'], next: '1234' }

You can then call

    http://flux.art.sy/query?keys[]=user:50000d:followers&maxResults=10&cursor=1234

To get the following 10 results. When there are no more results, you won't get a next
field in the result.

To query the union of multiple sets, just pass the sets' keys as separate arguments to the `keys[]` parameter. For example, to find the union of all followers of either user:50000d or user:60000e:

    http://flux.art.sy/query?keys[]=user:50000d:followers&keys[]=user:60000e:followers

Queries can be restricted to ranges of scores using one or both of the `minScore` and `maxScore` parameters, for example:

    http://flux.art.sy/query?keys[]=user:50000d:followers&minScore=1000&maxScore=5000

The results of the query will be all events in the score range `(minScore, maxScore]`. 

Counts
======

Flux keeps track of two types of counts: an estimate of the total number of
distinct items that have ever been added to the set and a count of the total
number of adds that have been executed against the set.

An estimate of the number of distinct items that have ever been added to a set is
available at `/distinct/`:

    http://flux.art.sy/distinct?keys[]=user:50000d:followers

When requesting a count across multiple sets, it is possible to query the approximate
cardinality of either the union or the intersection of the sets. For example, if set
"user:50000d:followers" has 20 elements and set "user:60000e:followers" has 20 elements, with the two sets having 10 elements in common, one could specify either `op=union` or
`op=intersection`, like so:

    http://flux.art.sy/distinct?op=union&keys[]=user:50000d:followers&keys[]=user:60000e:followers
    http://flux.art.sy/distinct?op=intersection&keys[]=user:50000d:followers&keys[]=user:60000e:followers

The first request would return a count of approximately 30 (the union cardinality),
while the second would return a count of approximately 10 (the intersection cardinality).

A count of the total number of adds is available at `/gross/`:

    http://flux.art.sy/gross?keys[]=user:50000d:followers

Both counts can be restricted to only events above a certain score with the `minScore` parameter, for example:

    http://flux.art.sy/distinct?keys[]=user:50000d:followers&minScore=1000
    http://flux.art.sy/gross?keys[]=user:50000d:followers&minScore=1000