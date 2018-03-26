# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

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
  case List.keyfind(Application.loaded_applications(), :distillery, 0) do
    nil -> System.get_env(name)
    _ -> "${#{name}}"
  end
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

config :logger, :console, metadata: [:request_id, :pid, :module]

config :chroxy, chrome_remote_debug_ports: 9222..9223

config :chroxy, Chroxy.ProxyListener,
  host: "127.0.0.1",
  port: 1431

config :chroxy, Chroxy.Endpoint,
  scheme: to_scheme.(envar.("CHROXY_ENDPOINT_SCHEME")) || :http,
  port: envar.("CHROXY_ENDPOINT_PORT") || 1330
