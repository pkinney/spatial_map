defmodule SpatialMapTest do
  use ExUnit.Case
  use ExUnitProperties

  doctest SpatialMap

  setup do
    map =
      SpatialMap.new(grid: [{0, 100, 0.1}, {0, 100, 0.2}])
      |> SpatialMap.put_feature!(
        %Geo.Polygon{coordinates: [[{3, 1}, {4, 5}, {2, 4}, {3, 1}]]},
        %{shape: :triangle}
      )
      |> SpatialMap.put_feature!(
        %Geo.Polygon{coordinates: [[{2, 3}, {5, 3}, {5, 6}, {2, 6}, {2, 3}]]},
        %{shape: :square}
      )
      |> SpatialMap.put_feature!(
        %Geo.LineString{coordinates: [{4, 7}, {6, 5}, {7, 7}]},
        %{shape: :line}
      )
      |> SpatialMap.put_feature!(
        %Geo.Point{coordinates: {2, 8}},
        %{shape: :point}
      )

    {:ok, map: map}
  end

  test "return empty list for query that doesn't intersect anything", %{map: map} do
    assert SpatialMap.query(map, {9, 9}) == []
  end

  test "return intersecting features", %{map: map} do
    results =
      SpatialMap.query_properties(
        map,
        %Geo.Polygon{coordinates: [[{1, 1}, {5, 1}, {5, 5}, {1, 5}, {1, 1}]]},
        :shape
      )

    assert results |> Enum.sort() == [:square, :triangle]
  end

  test "should not include features in the query's envelope and not in the actual geometry", %{
    map: map
  } do
    poly = %Geo.Polygon{
      coordinates: [[{0, 6}, {0, 10}, {4, 10}, {4, 6}, {0, 6}]]
    }

    poly_with_hole = %Geo.Polygon{
      coordinates: [[{0, 6}, {0, 10}, {4, 10}, {4, 6}, {0, 6}], [{1, 6}, {2, 9}, {3, 6}, {1, 6}]]
    }

    assert SpatialMap.query_properties(map, poly, :shape) |> Enum.sort() == [
             :line,
             :point,
             :square
           ]

    assert SpatialMap.query_properties(map, poly_with_hole, :shape) |> Enum.sort() == [
             :line,
             :square
           ]
  end
end
