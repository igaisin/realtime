defmodule Realtime.Nodes do
  @moduledoc """
  Handles common needs for :syn module operations
  """
  require Logger
  alias Realtime.Api.Tenant

  @doc """
  Gets the node to launch the Postgres connection on for a tenant.
  """
  @spec get_node_for_tenant(Tenant.t()) :: {:ok, node()} | {:error, term()}
  def get_node_for_tenant(nil), do: {:error, :tenant_not_found}

  def get_node_for_tenant(%Tenant{extensions: extensions, external_id: tenant_id}) do
    with region <- get_region(extensions),
         tenant_region <- platform_region_translator(region),
         node <- launch_node(tenant_id, tenant_region, node()) do
      {:ok, node}
    end
  end

  defp get_region(extensions) do
    extensions
    |> Enum.map(fn %{settings: %{"region" => region}} -> region end)
    |> Enum.uniq()
    |> hd()
  end

  @doc """
  Translates a region from a platform to the closest Supabase tenant region
  """
  @spec platform_region_translator(String.t()) :: nil | binary()
  def platform_region_translator(tenant_region) when is_binary(tenant_region) do
    platform = Application.get_env(:realtime, :platform)
    region_mapping(platform, tenant_region)
  end

  defp region_mapping(:aws, tenant_region) do
    case tenant_region do
      "us-west-1" -> "us-west-1"
      "us-west-2" -> "us-west-1"
      "us-east-1" -> "us-east-1"
      "sa-east-1" -> "us-east-1"
      "ca-central-1" -> "us-east-1"
      "ap-southeast-1" -> "ap-southeast-1"
      "ap-northeast-1" -> "ap-southeast-1"
      "ap-northeast-2" -> "ap-southeast-1"
      "ap-southeast-2" -> "ap-southeast-2"
      "ap-south-1" -> "ap-southeast-1"
      "eu-west-1" -> "eu-west-2"
      "eu-west-2" -> "eu-west-2"
      "eu-west-3" -> "eu-west-2"
      "eu-central-1" -> "eu-west-2"
      _ -> nil
    end
  end

  defp region_mapping(:fly, tenant_region) do
    case tenant_region do
      "us-east-1" -> "iad"
      "us-west-1" -> "sea"
      "sa-east-1" -> "iad"
      "ca-central-1" -> "iad"
      "ap-southeast-1" -> "syd"
      "ap-northeast-1" -> "syd"
      "ap-northeast-2" -> "syd"
      "ap-southeast-2" -> "syd"
      "ap-south-1" -> "syd"
      "eu-west-1" -> "lhr"
      "eu-west-2" -> "lhr"
      "eu-west-3" -> "lhr"
      "eu-central-1" -> "lhr"
      _ -> nil
    end
  end

  defp region_mapping(_, tenant_region), do: tenant_region

  @doc """
  Lists the nodes in a region. Sorts by node name in case the list order
  is unstable.
  """

  @spec region_nodes(String.t()) :: [atom()]
  def region_nodes(region) when is_binary(region) do
    :syn.members(RegionNodes, region)
    |> Enum.map(fn {_pid, [node: node]} -> node end)
    |> Enum.sort()
  end

  @doc """
  Picks the node to launch the Postgres connection on.

  If there are not two nodes in a region the connection is established from
  the `default` node given.
  """
  @spec launch_node(String.t(), String.t(), atom()) :: atom()
  def launch_node(tenant_id, region, default) do
    case region_nodes(region) do
      [node] ->
        Logger.warning(
          "Only one region node (#{inspect(node)}) for #{region} using default #{inspect(default)}"
        )

        default

      [] ->
        Logger.warning("Zero region nodes for #{region} using #{inspect(default)}")
        default

      regions_nodes ->
        member_count = Enum.count(regions_nodes)
        index = :erlang.phash2(tenant_id, member_count)

        Enum.fetch!(regions_nodes, index)
    end
  end
end
