# Run the SIBYL dashboard.
#
#   Rscript app/run.R          # default: localhost:5151
#   PORT=8080 Rscript app/run.R
#
# Or via the justfile:
#   just dashboard
#
# Opens in a browser automatically. Requires ANTHROPIC_API_KEY in
# .Renviron and a built targets cache (`just pipeline`).

port <- as.integer(Sys.getenv("PORT", "5151"))
launch_browser <- !nzchar(Sys.getenv("SIBYL_NO_LAUNCH_BROWSER"))

cat(sprintf("Starting SIBYL dashboard on http://localhost:%d ...\n", port))
shiny::runApp(
  appDir        = "app",
  port          = port,
  host          = "127.0.0.1",
  launch.browser = launch_browser
)
