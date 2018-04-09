# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

try_int = fn
  (nil) -> nil
  (i) when is_integer(i) -> i
  (s) when is_binary(s) ->
    try do
      String.to_integer(s)
    rescue
      _ -> s
    end
end

envar = fn name ->
  #
  # https://github.com/ueberauth/ueberauth_google/issues/40
  #
  # Detects whether Distillery is currently loaded, which is the behavior when building a release,
  # via mix release, which calls a Distillery task.
  #
  # If Distillery is loaded, then presumably the release will eventually be run with `REPLACE_OS_VARS`
  # defined, which allows the boot script to replace all values in `sys.config` within the release
  # with proper values from the environment. In these cases, emit name of the environment variable
  # wrapped in ${} so the script provided by Distillery can fix them up at boot time.
  #
  # Otherwise it is presumed that the config file is being evaluated outside of running a release.
  # This can happen, for example, during local development or testing. When this is the case,
  # since the configuration is not to be compiled into anything else, it is safe to invoke
  # `System.get_env/1` right away to get the desired value.
  #
  res = case List.keyfind(Application.loaded_applications(), :distillery, 0) do
    nil -> System.get_env(name)
    _ -> "${#{name}}"
  end
  try_int.(res)
end

to_scheme = fn scheme ->
  case scheme do
    nil ->
      nil

    s ->
      case String.upcase(s) do
        "HTTPS" -> :https
        "HTTP" -> :http
      end
  end
end

parse_range = fn
  (nil, nil) -> nil
  (from, nil) ->
    [try_int.(from)]
  (nil, to) ->
    [try_int.(to)]
  (from, to) ->
    Range.new(try_int.(from), try_int.(to))
end


config :logger, :console, metadata: [:request_id, :pid, :module]

config :chroxy,
  chrome_remote_debug_ports: parse_range.(
    envar.("CHROXY_CHROME_PORT_FROM"),
    envar.("CHROXY_CHROME_PORT_TO")) || 9222..9227

config :chroxy, Chroxy.ProxyListener,
  host: envar.("CHROXY_PROXY_HOST") || "127.0.0.1",
  port: envar.("CHROXY_PROXY_PORT") || 1331

config :chroxy, Chroxy.Endpoint,
  scheme: to_scheme.(envar.("CHROXY_ENDPOINT_SCHEME")) || :http,
  port: envar.("CHROXY_ENDPOINT_PORT") || 1330

config :chroxy, Chroxy.ChromeServer,
  page_wait_ms: envar.("CHROXY_CHROME_SERVER_PAGE_WAIT_MS") || 50
