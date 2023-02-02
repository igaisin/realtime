defmodule Realtime.PromEx.Plugins.Tenant do
  @moduledoc false

  use PromEx.Plugin
  require Logger
  alias Realtime.Telemetry
  alias Realtime.Tenants
  alias Realtime.UsersCounter
  alias Realtime.Api

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    [
      concurrent_connections(poll_rate)
    ]
  end

  @impl true
  def event_metrics(_opts) do
    # Event metrics definitions
    [
      channel_events()
    ]
  end

  defp concurrent_connections(poll_rate) do
    Polling.build(
      :realtime_concurrent_connections,
      poll_rate,
      {__MODULE__, :execute_tenant_metrics, []},
      [
        last_value(
          [:realtime, :connections, :connected],
          event_name: [:realtime, :connections],
          description: "The total count of connected clients for a tenant.",
          measurement: :connected,
          tags: [:tenant]
        ),
        last_value(
          [:realtime, :connections, :limit_concurrent],
          event_name: [:realtime, :connections],
          description: "The total count of connected clients for a tenant.",
          measurement: :limit,
          tags: [:tenant]
        )
      ]
    )
  end

  def execute_tenant_metrics() do
    tenants = Tenants.list_connected_tenants(Node.self())

    for t <- tenants do
      count = UsersCounter.tenant_users(Node.self(), t)
      tenant = Api.get_tenant_by_external_id(t)

      Telemetry.execute(
        [:realtime, :connections],
        %{connected: count, limit: tenant.max_concurrent_users},
        %{tenant: t}
      )
    end
  end

  defp channel_events() do
    Event.build(
      :realtime_tenant_events,
      [
        sum(
          [:realtime, :channel, :events],
          event_name: [:realtime, :rate_counter, :channel, :events],
          measurement: :sum,
          description: "Sum of messages sent on a Realtime Channel.",
          tags: [:tenant]
        ),
        last_value(
          [:realtime, :channel, :events, :limit_per_second],
          event_name: [:realtime, :rate_counter, :channel, :events],
          measurement: :limit,
          description: "Rate limit of messages per second sent on a Realtime Channel.",
          tags: [:tenant]
        ),
        sum(
          [:realtime, :channel, :joins],
          event_name: [:realtime, :rate_counter, :channel, :events],
          measurement: :sum,
          description: "Sum of Realtime Channel joins.",
          tags: [:tenant]
        ),
        last_value(
          [:realtime, :channel, :joins, :limit_per_second],
          event_name: [:realtime, :rate_counter, :channel, :events],
          measurement: :limit,
          description: "Rate limit of joins per second on a Realtime Channel.",
          tags: [:tenant]
        )
      ]
    )
  end
end