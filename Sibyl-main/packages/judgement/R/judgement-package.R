#' judgement: the LLM layer of SIBYL
#'
#' Provides the contract between human language, an LLM, and MARTIN.
#'
#' Two production functions:
#'
#' - [propose_adjustments()] — given a narrative and a baseline projection,
#'   return a structured list of add-factor proposals on MARTIN equations,
#'   each with a rationale, an expected effect, and a confidence.
#' - [describe_projection()] — given a solved projection and the baseline,
#'   draft prose explaining the differences. Closes the round-trip loop:
#'   the description should match the narrative.
#'
#' Plus the central [adjustment()] S3 class that travels across the whole
#' pipeline (LLM proposes -> human approves -> bimets consumes -> report
#' renders).
#'
#' All LLM calls go through `ellmer` with structured outputs.
#'
#' @keywords internal
"_PACKAGE"
