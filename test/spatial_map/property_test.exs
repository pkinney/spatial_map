defmodule SpatialMap.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "intersection geometries are returned in query (local)" do
    check all features <- list_of(GeoStreamData.geometry()),
              geo <- GeoStreamData.geometry(),
              max_run_time: 15_000 do
      map =
        Enum.reduce(
          features,
          SpatialMap.new(storage_type: :local, grid: [{-180, 180, 1}, {-90, 90, 1}]),
          fn feature, acc ->
            SpatialMap.put_feature!(acc, feature, %{intersects: Topo.intersects?(feature, geo)})
          end
        )

      result = SpatialMap.query(map, geo)
      assert Enum.all?(result, & &1.properties.intersects)

      assert length(result) ==
               Enum.count(SpatialMap.list_features(map), & &1.properties.intersects)
    end
  end

  property "intersection geometries are returned in query (ets)" do
    check all features <- list_of(GeoStreamData.geometry()),
              geo <- GeoStreamData.geometry(),
              max_run_time: 15_000 do
      map =
        Enum.reduce(
          features,
          SpatialMap.new(storage_type: :ets, grid: [{-180, 180, 1}, {-90, 90, 1}]),
          fn feature, acc ->
            SpatialMap.put_feature!(acc, feature, %{intersects: Topo.intersects?(feature, geo)})
          end
        )

      result = SpatialMap.query(map, geo)
      assert Enum.all?(result, & &1.properties.intersects)

      assert length(result) ==
               Enum.count(SpatialMap.list_features(map), & &1.properties.intersects)
    end
  end
end
