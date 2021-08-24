defmodule SpatialMap do
  @moduledoc """
  A SpatialMap is meant to hold static features in a spatial plane and allow
  for searching for features by geospatial lookup.
  """

  defstruct ~w(storage_type local table feature_table features grid)a

  @type t() :: %__MODULE__{
          storage_type: :local | :ets,
          table: reference() | nil,
          feature_table: reference() | nil,
          local: map() | nil,
          features: map() | nil,
          grid: list({number(), number(), number})
        }

  @type geometry ::
          {number(), number()}
          | %Geo.Point{}
          | %Geo.MultiPoint{}
          | %Geo.LineString{}
          | %Geo.MultiLineString{}
          | %Geo.Polygon{}
          | %Geo.MultiPolygon{}

  alias __MODULE__.Feature

  @doc """
  Creates a new `SpatialMap` with the given options.

   - *storage_type* - can be either `:local` (default) or `:ets`.
     A `:local` storage type stores the features in a local map inside
     the `SpatialHash` struct.  An `:ets` storage type creates wan
     ETS table for feature storage. Default: `:local`

  - *table_name* - an atom specifying the name of the underlying ETS table.
    This is only used when storage_type is set to :ets and is required if
    more than one `SpatialMap` of type `:ets` is created on the current node.

  - *access* - when creating a `SpatialMap` of type `:ets`, this specifies the
    access protection for the underlying table.  Default: `:public`

  - *grid* - specifies the grid to be used with the underlying `SpatialHash`
    of the map.  Please see `SpacialHash` documentation for more information.
    Default: `SpatialHash.world_grid()`

  ## Examples

      iex> SpatialMap.new()
      ...> |> SpatialMap.storage_type()
      :local

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    map = %__MODULE__{
      storage_type: Keyword.get(opts, :storage_type, :local),
      grid: Keyword.get(opts, :grid, SpatialHash.world_grid())
    }

    case map.storage_type do
      :ets ->
        table_name = Keyword.get(opts, :table_name, :spatial_map)
        feature_table_name = Keyword.get(opts, :feature_table_name, :"#{table_name}_features")
        ets_access = Keyword.get(opts, :ets_access, :public)

        table = :ets.new(table_name, [:bag, ets_access, read_concurrency: true])
        feature_table = :ets.new(feature_table_name, [:set, ets_access, read_concurrency: true])

        %__MODULE__{map | table: table, feature_table: feature_table}

      _ ->
        %__MODULE__{map | local: %{}, features: %{}}
    end
  end

  @doc """
  Returns the type of storage for the given `SpatialMap`.

  ## Exmaples

      iex> SpatialMap.new(storage_type: :ets)
      ...> |> SpatialMap.storage_type()
      :ets
  """
  @spec storage_type(t()) :: :local | :ets
  def storage_type(%__MODULE__{storage_type: t}), do: t

  @doc """
  Adds a new feature, which consists of a geometry and a set of metadata, and 
  returns a reference for the feature the updated map.

  *Important Note*: For larger features and small grid cell sizes, this function
  can take an extremely long time.  See README.md for more information about 
  this tradoff.

  ### Example

      iex> {map, ref} = 
      ...>   SpatialMap.new()
      ...>   |> SpatialMap.put_feature(%Geo.Point{coordinates: {-90, 30}}, %{foo: :bar})
      ...> SpatialMap.get_feature(map, ref) |> Map.get(:properties)
      %{foo: :bar}
  """
  @spec put_feature(t(), geometry(), map()) :: {t(), reference()}
  def put_feature(%__MODULE__{} = map, geometry, metadata \\ %{}) do
    {map, feature} = create_feature(map, geometry, metadata)

    {do_update_over_envelope(map, feature.envelope, &add_to_cell(&1, &2, &3, feature.id)),
     feature.id}
  end

  @doc """
  Adds a feature to a map and only returns the SpatialMap. This is useful for chaining
  mulitple features 

  ### Example

      iex> SpatialMap.new()
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {-90, 30}}, %{foo: :bar})
      ...> |> SpatialMap.query({-90, 30}) 
      ...> |> List.first()
      ...> |> Map.get(:properties)
      %{foo: :bar}
  """
  @spec put_feature!(t(), geometry(), map()) :: t()
  def put_feature!(map, geometry, metadata \\ %{}) do
    put_feature(map, geometry, metadata) |> elem(0)
  end

  @doc """
  Returns the feature from the SpatialMap for the given refence or nil if one is not found.

  ### Example

      iex> {map, ref} = 
      ...>   SpatialMap.new()
      ...>   |> SpatialMap.put_feature(%Geo.Point{coordinates: {-90, 30}}, %{foo: :bar})
      ...> SpatialMap.get_feature(map, ref) |> Map.get(:properties)
      %{foo: :bar}

      iex> SpatialMap.new()
      ...> |> SpatialMap.get_feature(make_ref())
      nil

      iex> {map, ref} = 
      ...>   SpatialMap.new(storage_type: :ets)
      ...>   |> SpatialMap.put_feature(%Geo.Point{coordinates: {-90, 30}}, %{foo: :bar})
      ...> SpatialMap.get_feature(map, ref) |> Map.get(:properties)
      %{foo: :bar}

      iex> SpatialMap.new(storage_type: :ets)
      ...> |> SpatialMap.get_feature(make_ref())
      nil
  """
  @spec get_feature(t(), reference()) :: Feature.t() | nil
  def get_feature(%__MODULE__{storage_type: :local} = map, ref) do
    Map.get(map.features, ref)
  end

  def get_feature(%__MODULE__{storage_type: :ets} = map, ref) do
    :ets.lookup(map.feature_table, ref)
    |> case do
      [] -> nil
      [{_, feature} | _] -> feature
    end
  end

  @doc """
  Moves a feature from one geometry to another.

  *Important Note*: This is an even more expensive operation than `put_feature` in that it
  has to iterate over the geometry of the orignal position and the new geometry.

  ### Example

      iex> {map, ref} = 
      ...>   SpatialMap.new()
      ...>   |> SpatialMap.put_feature(%Geo.Point{coordinates: {-90, 30}}, %{foo: :bar})
      ...> map
      ...> |> SpatialMap.move_feature(ref, %Geo.Point{coordinates: {-110, 40}})
      ...> |> SpatialMap.query({-90, 30})
      []
      
      iex> {map, ref} = 
      ...>   SpatialMap.new(storaget_type: :ets)
      ...>   |> SpatialMap.put_feature(%Geo.Point{coordinates: {-90, 30}}, %{foo: :bar})
      ...> map
      ...> |> SpatialMap.move_feature(ref, %Geo.Point{coordinates: {-110, 40}})
      ...> |> SpatialMap.query({-90, 30})
      []
  """
  @spec move_feature(t(), reference(), geometry()) :: t()
  def move_feature(%__MODULE__{} = map, ref, geometry) do
    case get_feature(map, ref) do
      nil ->
        map

      feature ->
        new_envelope = Envelope.from_geo(geometry)

        do_update_over_envelope(map, feature.envelope, &delete_from_cell(&1, &2, &3, ref))
        |> do_update_over_envelope(new_envelope, &add_to_cell(&1, &2, &3, ref))
        |> put_feature_in_storage(%{feature | envelope: new_envelope, geometry: geometry})
    end
  end

  def move_feature(map, _, _), do: map

  @doc """
  Deltes a feature from the SpatialMap.

  *Imprtant Note*: this function also operates on all the cells occupied by the features,
  so it is as expensive as adding a new feature.

  ### Example

      iex> {map, ref} = 
      ...>   SpatialMap.new()
      ...>   |> SpatialMap.put_feature(%Geo.Point{coordinates: {-90, 30}}, %{foo: :bar})
      ...> map
      ...> |> SpatialMap.delete_feature(ref)
      ...> |> SpatialMap.query({-90, 30})
      []
  """
  @spec delete_feature(t(), reference()) :: t()
  def delete_feature(%__MODULE__{} = map, ref) do
    get_feature(map, ref)
    |> case do
      %Feature{envelope: envelope} ->
        do_update_over_envelope(map, envelope, &delete_from_cell(&1, &2, &3, ref))
        |> delete_feature_from_storage(ref)

      _ ->
        map
    end
  end

  @doc """
  Returns all features in the SpatialMap
  """
  @spec list_features(t()) :: list(Feature.t())
  def list_features(%__MODULE__{storage_type: :local} = map), do: Map.values(map.features)

  def list_features(%__MODULE__{storage_type: :ets} = map) do
    :ets.tab2list(map.feature_table) |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Returns the number of features in the SpacialMap

  ### Examples

      iex> SpatialMap.new()
      ...> |> SpatialMap.count_features()
      0

      iex> SpatialMap.new()
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {1, 3}}, %{name: :a})
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {2, 1}}, %{name: :b})
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {4, 3}}, %{name: :c})
      ...> |> SpatialMap.count_features()
      3
      
      iex> SpatialMap.new(storage_type: :ets)
      ...> |> SpatialMap.count_features()
      0

      iex> SpatialMap.new(storage_type: :ets)
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {1, 3}}, %{name: :a})
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {2, 1}}, %{name: :b})
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {4, 3}}, %{name: :c})
      ...> |> SpatialMap.count_features()
      3

  """
  @spec count_features(t()) :: non_neg_integer()
  def count_features(%__MODULE__{storage_type: :local} = map), do: map_size(map.features)

  def count_features(%__MODULE__{storage_type: :ets} = map) do
    :ets.info(map.feature_table, :size)
  end

  @doc """
  Queries the SpatialMap for all featurs that intersect the given geometry.
  """
  @spec query(t(), geometry()) :: list(Feature.t())
  def query(%__MODULE__{} = map, geometry) do
    envelope = Envelope.from_geo(geometry)

    do_envelope_query(map, envelope)
    |> Enum.map(&get_feature(map, &1))
    |> Enum.filter(&Topo.intersects?(geometry, &1.geometry))
  end

  @doc """
  Same as `query/2`, but returns the properties from the resulting features.

  ### Examples

      iex> SpatialMap.new()
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {1, 3}}, %{name: :a})
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {2, 1}}, %{name: :b})
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {4, 3}}, %{name: :c})
      ...> |> SpatialMap.query_properties(%Geo.Polygon{coordinates: [[{0, 0}, {0, 5}, {5, 0}, {0, 0}]]})
      [%{name: :a}, %{name: :b}]

  """
  @spec query_properties(t(), geometry()) :: list(map())
  def query_properties(map, geometry) do
    query(map, geometry) |> Enum.map(& &1.properties)
  end

  @doc """
  Same as `query_properties/2`, but returns the value of the given key for the resulting features.

  ### Examplesref

      iex> SpatialMap.new()
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {1, 3}}, %{name: :a})
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {2, 1}}, %{name: :b})
      ...> |> SpatialMap.put_feature!(%Geo.Point{coordinates: {4, 3}}, %{name: :c})
      ...> |> SpatialMap.query_properties(%Geo.Polygon{coordinates: [[{0, 0}, {0, 5}, {5, 0}, {0, 0}]]}, :name)
      [:a, :b]
  """
  @spec query_properties(t(), geometry(), any()) :: list(any())
  def query_properties(map, geometry, key) do
    query(map, geometry) |> Enum.map(&Map.get(&1.properties, key))
  end

  defp do_envelope_query(%__MODULE__{} = map, %Envelope{} = envelope) do
    do_update_over_envelope(MapSet.new(), envelope, map.grid, fn acc, x, y ->
      do_query_map_cell(map, x, y)
      |> Enum.reduce(acc, &MapSet.put(&2, &1))
    end)
    |> MapSet.to_list()
  end

  defp do_query_map_cell(%__MODULE__{storage_type: :local, local: local}, x, y) do
    Map.get(local, {x, y}, [])
  end

  defp do_query_map_cell(%__MODULE__{storage_type: :ets, table: table}, x, y) do
    :ets.lookup(table, {x, y}) |> Enum.map(&elem(&1, 1))
  end

  defp add_to_cell(%__MODULE__{storage_type: :local} = map, x, y, ref) do
    %{map | local: map.local |> Map.put({x, y}, [ref | Map.get(map.local, {x, y}, [])])}
  end

  defp add_to_cell(%__MODULE__{storage_type: :ets} = map, x, y, ref) do
    true = :ets.insert(map.table, {{x, y}, ref})
    map
  end

  defp delete_from_cell(%__MODULE__{storage_type: :local} = map, x, y, ref) do
    cell = Map.get(map.local, {x, y}, [])
    %{map | local: map.local |> Map.put({x, y}, List.delete(cell, ref))}
  end

  defp delete_from_cell(%__MODULE__{storage_type: :ets} = map, x, y, ref) do
    true = :ets.delete_object(map.table, {{x, y}, ref})
    map
  end

  defp create_feature(map, geometry, properties) do
    ref = make_ref()
    envelope = Envelope.from_geo(geometry)

    feature = %Feature{
      id: ref,
      geometry: geometry,
      envelope: envelope,
      properties: properties
    }

    {put_feature_in_storage(map, feature), feature}
  end

  defp put_feature_in_storage(%__MODULE__{storage_type: :local} = map, feature) do
    %{map | features: map.features |> Map.put(feature.id, feature)}
  end

  defp put_feature_in_storage(%__MODULE__{storage_type: :ets} = map, feature) do
    :ets.insert(map.feature_table, {feature.id, feature})
    map
  end

  defp delete_feature_from_storage(%__MODULE__{storage_type: :local} = map, ref) do
    %{map | features: map.features |> Map.delete(ref)}
  end

  defp delete_feature_from_storage(%__MODULE__{storage_type: :ets} = map, ref) do
    :ets.delete(map.feature_table, ref)
    map
  end

  defp do_update_over_envelope(%__MODULE__{grid: grid} = map, envelope, func) do
    do_update_over_envelope(map, envelope, grid, func)
  end

  defp do_update_over_envelope(start, envelope, grid, func) do
    [x_range, y_range] = SpatialHash.hash_range(envelope, grid)

    Enum.reduce(x_range, start, fn x, x_acc ->
      Enum.reduce(y_range, x_acc, fn y, y_acc ->
        func.(y_acc, x, y)
      end)
    end)
  end
end
