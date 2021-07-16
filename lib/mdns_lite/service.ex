defmodule MdnsLite.Service do
  defstruct name: "",
            txt_payload: [""],
            port: 0,
            priority: 0,
            protocol: "",
            transport: "",
            type: "",
            weight: 0

  @type t() :: %__MODULE__{
          name: String.t(),
          txt_payload: [String.t()],
          port: 1..65535,
          priority: 0..255,
          protocol: String.t(),
          transport: String.t(),
          type: String.t(),
          weight: 0..255
        }

  def new(%__MODULE__{} = service), do: service

  def new(opts) do
    struct(__MODULE__, opts)
    |> add_type()
  end

  defp add_type(%{type: ""} = service) do
    %{service | type: "_#{service.protocol}._#{service.transport}"}
  end
end
