# SpatialMap

![Build Status](https://github.com/pkinney/spatial_map/actions/workflows/ci.yaml/badge.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/spatial_map.svg)](https://hex.pm/packages/spatial_map)

> :warning: This is still a bit of a work in progress.

Storage mechanism for geospatial features that is optimized for fast
intersections checks with other geometries. Computational cost for geometries are
roughly constant in sparse maps, but this comes at the cost of very expensive
addition and mutation of features in the map.

On creation, a `SpatialMap` creates a hash function for locations that effectively divides the world
in to an orthogonal grid of some standard size. Points that occupy the same grid cells will return
the same hash result. When a feature is added to the map, its envelope is determined and the
hashes for all points within that envelope are computed. A map is maintained from hash result
to list of features.

When a query is performed, the hash result of the query is calculated which allows for
very fast lookup. Finally, an intersection check is performed against original geometry of
each feature. The set of features returned are those that definitely intersect the query
geometry.

## Performance Consideration

In general, querying for features that intersect a point is a roughly linear operation whereas
adding or modifying features on a `SpatialMap` is vastly magnitude more expensive.

Tuning of the performance is done via the size of grid into which the world is divided:

- When the grid cells are smaller, there are generally fewer features within that cell and
  the intersection check becomes faster. Larger grid cells contain more features and
  therefore have more work to be done during the final step above (they have more false-positive
  results in the initial hash lookup).

- At the same time, features must be added to all cells that they hash to, which means the work
  performed when adding features increases as grid size decreases.

With this in mind, the most appropriate use case for this method of geospatial storage is when
all the features are known at start-up and are not expected to change. A large amount of time can
be dedicated to populating the map at startup while lookups will be extremely fast during runtime.

## Storage Type

This library supports two types of storage for the underlying spatial hash map: `:local` and `:ets`.

- **Local** - The underlying map is stored on the `SpatialMap`. This is suitable when a single process
  will be responsible for both loading and answering queries. There might be methods where a `SpatialMap`
  can be created and then copied to multiple processes, but there may be additional memory overhead.

- **ETS** - The underlying map and feature information is stored in an ETS table. This is suitable for
  access from multiple processes and potentially allows for more scalability, especially when changes to the
  map might be necessary.

## Installation

The package can be installed by adding `spatial_map` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:spatial_map, "~> 0.1"}
  ]
end
```

Docs can be found at: [https://hexdocs.pm/spatial_map](https://hexdocs.pm/spatial_map).

## Usage

```elixir
map = SpatialMap.new()
map = SpatialMap.new(grid: [{0, 100, 0.1}, {0, 100, 0.1}], storage_type: :ets)

{map, ref} = SpatialMap.put_feature(map, %Geo.Polygon{...}, %{foo: bar})
intersections = SpatialMap.query(map, %Geo.LineString{...})
```
