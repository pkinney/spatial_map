defmodule SpatialMap.Feature do
  defstruct ~w(id properties envelope geometry)a

  @type t() :: %__MODULE__{
          id: reference(),
          properties: map(),
          envelope: Envelope.t(),
          geometry: SpatialMap.geometry()
        }
end
