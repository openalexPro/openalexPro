# Note: Any variables prefixed with `.` are used for text
# replacement in the Makevars.in and Makevars.win.in

# check the packages MSRV first
source("tools/msrv.R")

# check DEBUG and NOT_CRAN environment variables
env_debug <- Sys.getenv("DEBUG")
env_not_cran <- Sys.getenv("NOT_CRAN")

# check if the vendored zip file exists
vendor_exists <- file.exists("src/rust/vendor.tar.xz")

is_not_cran <- env_not_cran != ""
is_debug <- env_debug != ""

if (is_debug) {
  # if we have DEBUG then we set not cran to true
  # CRAN is always release build
  is_not_cran <- TRUE
  message("Creating DEBUG build.")
}

if (!is_not_cran) {
  message("Building for CRAN.")
}

# we set cran flags only if NOT_CRAN is empty and if
# the vendored crates are present.
.cran_flags <- ifelse(
  !is_not_cran && vendor_exists,
  "-j 2 --offline",
  ""
)

# when DEBUG env var is present we use `--debug` build
.profile <- ifelse(is_debug, "", "--release")
.clean_targets <- ifelse(is_debug, "", "$(TARGET_DIR)")

# We specify this target when building for webR
webr_target <- "wasm32-unknown-emscripten"

# here we check if the platform we are building for is webr
is_wasm <- identical(R.version$platform, webr_target)

# print to terminal to inform we are building for webr
if (is_wasm) {
  message("Building for WebR")
}

# we check if we are making a debug build or not
# if so, the LIBDIR environment variable becomes:
# LIBDIR = $(TARGET_DIR)/{wasm32-unknown-emscripten}/debug
# this will be used to fill out the LIBDIR env var for Makevars.in
target_libpath <- if (is_wasm) "wasm32-unknown-emscripten" else NULL
cfg <- if (is_debug) "debug" else "release"

# used to replace @LIBDIR@
.libdir <- paste(c(target_libpath, cfg), collapse = "/")

# use this to replace @TARGET@
# we specify the target _only_ on webR
# there may be use cases later where this can be adapted or expanded
.target <- ifelse(is_wasm, paste0("--target=", webr_target), "")

# add panic exports only for WASM builds
.panic_exports <- ifelse(
  is_wasm,
  "CARGO_PROFILE_DEV_PANIC=\"abort\" CARGO_PROFILE_RELEASE_PANIC=\"abort\" ",
  ""
)

# Detect macOS deployment target so Rust/DuckDB objects are compiled for the
# same macOS version that R's linker targets.  Without this, bundled DuckDB
# uses the system Xcode SDK (e.g. 15.5) while R links against 15.0, producing
# dozens of ld warnings that R CMD check promotes to errors.
#
# Strategy:
#   1. Read MACOSX_DEPLOYMENT_TARGET from R's own Makeconf (most reliable).
#   2. Fall back to the MACOSX_DEPLOYMENT_TARGET env var if the Makeconf
#      variable is absent.
#   3. If still unknown, use the version R itself was built against (via
#      R.version$os parsing), which always matches R's linker expectation.
#   4. On non-macOS / WASM, emit an empty string (no-op).
.macosx_deployment_target_export <- ""
if (.Platform$OS.type != "windows" && !is_wasm) {
  mdt <- ""

  # 1. R's Makeconf
  makeconf <- file.path(R.home("etc"), "Makeconf")
  if (file.exists(makeconf)) {
    lines <- readLines(makeconf, warn = FALSE)
    hit <- grep("^MACOSX_DEPLOYMENT_TARGET[[:space:]]*=", lines, value = TRUE)
    if (length(hit) > 0L) {
      mdt <- trimws(sub("^[^=]+=", "", hit[1L]))
    }
  }

  # 2. Env var fallback
  if (!nzchar(mdt)) {
    mdt <- Sys.getenv("MACOSX_DEPLOYMENT_TARGET")
  }

  # 3. Parse -mmacosx-version-min from R's LDFLAGS or CFLAGS in Makeconf
  if (!nzchar(mdt) && file.exists(makeconf)) {
    lines <- readLines(makeconf, warn = FALSE)
    for (var in c("LDFLAGS", "CFLAGS", "CXXFLAGS")) {
      hit <- grep(paste0("^", var, "[[:space:]]*="), lines, value = TRUE)
      if (length(hit) > 0L) {
        m <- regmatches(
          hit[1L],
          regexpr("-mmacosx-version-min=([0-9]+\\.[0-9]+(\\.[0-9]+)?)", hit[1L])
        )
        if (length(m) > 0L && nzchar(m)) {
          mdt <- sub("-mmacosx-version-min=", "", m)
          break
        }
      }
    }
  }

  # 4. Read minos from R's own libR.dylib via otool (most reliable fallback)
  if (!nzchar(mdt)) {
    libR_paths <- Sys.glob(file.path(R.home("lib"), "libR*.dylib"))
    if (length(libR_paths) > 0L) {
      ot <- tryCatch(
        system2("otool", c("-l", libR_paths[1L]), stdout = TRUE, stderr = FALSE),
        error = function(e) character(0)
      )
      # LC_BUILD_VERSION block contains "minos X.Y" (macOS 15+)
      # LC_VERSION_MIN_MACOSX block contains "version X.Y.Z" (older)
      minos_hit <- grep("\\bminos\\b", ot, value = TRUE, ignore.case = TRUE)
      if (length(minos_hit) > 0L) {
        m <- regmatches(minos_hit[1L], regexpr("[0-9]+\\.[0-9]+(\\.[0-9]+)?", minos_hit[1L]))
        if (length(m) > 0L && nzchar(m)) mdt <- m
      }
    }
  }

  if (nzchar(mdt)) {
    message("Setting MACOSX_DEPLOYMENT_TARGET=", mdt, " for Rust/DuckDB build.")
    .macosx_deployment_target_export <- paste0("export MACOSX_DEPLOYMENT_TARGET=", mdt, " &&")
  }
}

# read in the Makevars.in file checking
is_windows <- .Platform[["OS.type"]] == "windows"

# if windows we replace in the Makevars.win.in
mv_fp <- ifelse(
  is_windows,
  "src/Makevars.win.in",
  "src/Makevars.in"
)

# set the output file
mv_ofp <- ifelse(
  is_windows,
  "src/Makevars.win",
  "src/Makevars"
)

# delete the existing Makevars{.win/.wasm}
if (file.exists(mv_ofp)) {
  message("Cleaning previous `", mv_ofp, "`.")
  invisible(file.remove(mv_ofp))
}

# read as a single string
mv_txt <- readLines(mv_fp)

# replace placeholder values
new_txt <- gsub("@CRAN_FLAGS@", .cran_flags, mv_txt) |>
  gsub("@PROFILE@", .profile, x = _) |>
  gsub("@CLEAN_TARGET@", .clean_targets, x = _) |>
  gsub("@LIBDIR@", .libdir, x = _) |>
  gsub("@TARGET@", .target, x = _) |>
  gsub("@PANIC_EXPORTS@", .panic_exports, x = _) |>
  gsub("@MACOSX_DEPLOYMENT_TARGET_EXPORT@", .macosx_deployment_target_export, x = _)

message("Writing `", mv_ofp, "`.")
con <- file(mv_ofp, open = "wb")
writeLines(new_txt, con, sep = "\n")
close(con)

message("`tools/config.R` has finished.")
