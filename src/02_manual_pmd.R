################################################################################
# ML II Group Assignment — Ex. 7.2
# Francesco Serra | Job Siegmann | Sadra Daneshvar
################################################################################

rm(list = ls())                                                        # clear workspace

# =========================
# 0) Packages
# =========================
req_pkgs <- c("PMA", "dplyr", "tibble", "tidyr", "ggplot2", "xtable", "stringr")  # required packages
missing_pkgs <- setdiff(req_pkgs, rownames(installed.packages()))                # missing packages
if (length(missing_pkgs) > 0) {                                                  # fail with setup guidance
  stop(sprintf(
    "Missing R packages: %s. From the repository root, run `make setup`.",
    paste(missing_pkgs, collapse = ", ")
  ), call. = FALSE)
}

library(PMA)                                                             # PMD/SPC tools
library(dplyr)                                                           # data wrangling
library(tibble)                                                          # tibbles
library(tidyr)                                                           # reshaping
library(ggplot2)                                                         # plotting
library(xtable)                                                          # LaTeX tables
library(stringr)                                                         # string helpers

# =========================
# 1) Helpers: norms + thresholding
# =========================
l1_norm <- function(x) sum(abs(x))                                       # L1 norm
l2_norm <- function(x) sqrt(sum(x^2))                                    # L2 norm

normalize_l2 <- function(x) {                                            # L2 normalize
  x <- as.vector(x)                                                      # coerce to vector
  nrm <- l2_norm(x)                                                      # compute L2 norm
  if (!is.finite(nrm) || nrm <= 0) return(rep(0, length(x)))             # handle degenerate
  x / nrm                                                                # scale to unit norm
}

soft_threshold <- function(x, lambda) {                                  # soft-threshold
  x <- as.vector(x)                                                      # coerce to vector
  sign(x) * pmax(abs(x) - lambda, 0)                                     # apply threshold
}

threshold_then_normalize <- function(x, lambda) {                        # shrink then normalize
  normalize_l2(soft_threshold(x, lambda))                                # compose ops
}

# =========================
# 2) Lambda search for L1 target
# =========================
lambda_for_l1_target <- function(x, target, tol = 1e-6, max_iter = 100) { # binary search lambda
  x <- as.vector(x)                                                      # coerce to vector
  target <- as.numeric(target)[1]                                        # scalar target

  if (!is.finite(target) || target <= 0) return(0)                       # guard invalid target
  if (all(x == 0) || !is.finite(max(abs(x)))) return(0)                  # guard invalid x

  x0 <- normalize_l2(x)                                                  # normalize at lambda=0
  if (l1_norm(x0) <= target + tol) return(0)                             # inactive constraint

  lo <- 0                                                                # lower bound
  hi <- max(abs(x))                                                      # upper bound

  for (it in seq_len(max_iter)) {                                        # iterate search
    mid <- 0.5 * (lo + hi)                                               # midpoint
    z <- threshold_then_normalize(x, mid)                                # threshold+normalize

    if (all(z == 0)) {                                                   # if all killed
      hi <- mid                                                          # reduce hi
      next                                                               # continue loop
    }

    val <- l1_norm(z)                                                    # current L1
    if (abs(val - target) < tol) return(mid)                             # stop if close

    if (val > target) lo <- mid else hi <- mid                           # update bracket
  }

  0.5 * (lo + hi)                                                        # return best mid
}

# =========================
# 3) Single-factor PMD (SFPD)
# =========================
SFPD <- function(X, target_u, target_v, max_iter = 100, tol = 1e-6) {     # one-factor PMD
  X <- as.matrix(X)                                                      # coerce to matrix
  storage.mode(X) <- "double"                                            # enforce double

  n <- nrow(X); p <- ncol(X)                                             # dimensions
  target_u <- as.numeric(target_u)[1]                                    # scalar target_u
  target_v <- as.numeric(target_v)[1]                                    # scalar target_v

  sv <- svd(X, nu = 1, nv = 1)                                           # rank-1 SVD init
  u <- as.vector(sv$u[, 1])                                              # init u
  v <- as.vector(sv$v[, 1])                                              # init v

  for (it in seq_len(max_iter)) {                                        # iterate updates
    xu <- as.vector(X %*% v)                                             # u score direction
    lam_u <- lambda_for_l1_target(xu, target = target_u, tol = tol, max_iter = 100) # lambda u
    u_new <- threshold_then_normalize(xu, lam_u)                         # update u

    xv <- as.vector(t(X) %*% u_new)                                      # v score direction
    lam_v <- lambda_for_l1_target(xv, target = target_v, tol = tol, max_iter = 100) # lambda v
    v_new <- threshold_then_normalize(xv, lam_v)                         # update v

    crit <- 1 - abs(sum(v_new * v))                                      # convergence criterion
    u <- u_new                                                           # set u
    v <- v_new                                                           # set v
    if (crit < tol) break                                                # stop if converged
  }

  d <- as.numeric(t(u) %*% X %*% v)                                      # singular value
  list(u = u, v = v, d = d, iter = it)                                   # return fit
}

# =========================
# 4) Multi-factor PMD (MFPMD)
# =========================
MFPMD <- function(X, K, target_u, target_v, max_iter = 100, tol = 1e-6) { # multi-factor PMD
  X <- as.matrix(X)                                                      # coerce to matrix
  storage.mode(X) <- "double"                                            # enforce double

  n <- nrow(X); p <- ncol(X)                                             # dimensions
  K <- as.integer(K)[1]                                                  # scalar K

  U <- matrix(0, n, K)                                                   # allocate U
  V <- matrix(0, p, K)                                                   # allocate V
  D <- numeric(K)                                                        # allocate D

  X_def <- X                                                             # deflated copy

  for (k in seq_len(K)) {                                                # loop components
    fit <- SFPD(X_def, target_u, target_v, max_iter = max_iter, tol = tol) # fit factor
    U[, k] <- fit$u                                                      # store u_k
    V[, k] <- fit$v                                                      # store v_k
    D[k]   <- fit$d                                                      # store d_k

    X_def <- X_def - fit$d * (fit$u %*% t(fit$v))                         # deflate matrix
  }

  colnames(U) <- paste0("U", seq_len(K))                                 # name U cols
  colnames(V) <- paste0("V", seq_len(K))                                 # name V cols
  list(u = U, v = V, d = D)                                              # return fit
}

################################################################################
# Exercise 7.2 — Manual MFPMD vs PMA::PMD() on FIFA2017_NL
################################################################################

# =========================
# 5) Load data
# =========================
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE) # Rscript path
repo_root <- if (length(script_arg) > 0) {                               # derive repository root
  script_path <- normalizePath(sub("^--file=", "", script_arg[1]), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
} else {
  normalizePath(getwd(), mustWork = TRUE)                                # interactive fallback
}

data_path <- Sys.getenv(                                                 # private data can live outside Git
  "FIFA2017_NL_PATH",
  unset = file.path(repo_root, "data", "FIFA2017_NL.RData")
)
if (!file.exists(data_path)) {                                           # actionable data-contract failure
  stop(paste0(
    "Dataset not found at `", data_path, "`. ",
    "See data/README.md and set FIFA2017_NL_PATH to your authorized copy."
  ), call. = FALSE)
}
load(data_path)                                                          # load .RData
stopifnot(exists("fifa"))                                                # check object exists

fifa_raw <- fifa                                                         # keep raw copy

# =========================
# 6) Skills-only matrix
# =========================
econ_candidates <- c("eur_value", "eur_wage", "eur_release_clause")       # econ candidates
econ_vars <- intersect(econ_candidates, names(fifa_raw))                 # existing econ vars

num_cols <- names(fifa_raw)[sapply(fifa_raw, is.numeric)]                # numeric columns
skill_candidates <- setdiff(num_cols, econ_vars)                         # numeric non-econ

skill_vars <- skill_candidates[sapply(fifa_raw[skill_candidates], function(z) { # 0-100 filter
  z <- z[!is.na(z)]                                                      # drop NA
  length(z) > 0 && all(z >= 0 & z <= 100)                                # bounds check
})]

if (length(skill_vars) < 10) skill_vars <- setdiff(num_cols, econ_vars)  # fallback skills set

X_raw <- fifa_raw %>%                                                    # start matrix build
  select(all_of(skill_vars)) %>%                                         # select skills
  as.matrix()                                                            # convert to matrix

keep <- complete.cases(X_raw)                                            # complete-case mask
X_raw <- X_raw[keep, , drop = FALSE]                                     # apply mask

X <- scale(X_raw, center = TRUE, scale = FALSE)                          # center only
X <- as.matrix(X)                                                        # ensure matrix
storage.mode(X) <- "double"                                              # enforce double

n <- nrow(X); p <- ncol(X)                                               # dimensions
cat(sprintf("Exercise 7.2: matrix dims n=%d, p=%d\n", n, p))              # print dims
cat(sprintf("Skill variables used: %d\n\n", p))                          # print p

# =========================
# 7) Settings
# =========================
set.seed(1363)                                                           # reproducibility seed

K        <- 5                                                            # number of factors
max_iter <- 100                                                          # iteration cap
tol      <- 1e-6                                                         # convergence tol

target_u <- unname(drop(as.numeric(sqrt(n))))                            # L1 target for u
target_v <- unname(drop(as.numeric(3)))                                  # L1 target for v

X <- as.matrix(X)                                                        # re-assert matrix
dimnames(X) <- list(NULL, colnames(X))                                   # drop rownames, keep colnames

# =========================
# 8) Built-in PMD (PMA)
# =========================
pmd_builtin <- PMD(                                                      # run PMA::PMD
  x       = X,                                                           # input matrix
  sumabsu = as.numeric(target_u)[1],                                      # u sparsity target
  sumabsv = as.numeric(target_v)[1],                                      # v sparsity target
  K       = as.integer(K)[1],                                            # number of factors
  center  = FALSE,                                                       # already centered
  niter   = as.integer(max_iter)[1],                                     # max iterations
  trace   = FALSE,                                                       # no tracing
  type    = "standard",                                                  # standard PMD
  vpos    = FALSE,                                                       # no positivity constraint
  vneg    = FALSE                                                        # no negativity constraint
)

# =========================
# 9) Manual MFPMD
# =========================
pmd_manual <- MFPMD(                                                     # run manual MFPMD
  X        = X,                                                          # input matrix
  K        = K,                                                          # number of factors
  target_u = target_u,                                                   # u target
  target_v = target_v,                                                   # v target
  max_iter = max_iter,                                                   # max iterations
  tol      = tol                                                         # tolerance
)

# =========================
# 10) Align signs
# =========================
for (k in seq_len(K)) {                                                  # loop components
  s <- sum(pmd_builtin$v[, k] * pmd_manual$v[, k])                        # dot product
  if (is.finite(s) && s < 0) {                                           # flip if opposite
    pmd_manual$u[, k] <- -pmd_manual$u[, k]                               # flip u_k
    pmd_manual$v[, k] <- -pmd_manual$v[, k]                               # flip v_k
  }
}

# =========================
# 11) Outputs: tables + scatter
# =========================
out_dir <- Sys.getenv(                                                    # generated artifacts stay outside source
  "FIFA_PMD_RESULTS_DIR",
  unset = file.path(repo_root, "results", "manual_pmd")
)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)              # create folder

V_df <- tibble(                                                          # full V comparison table
  Feature = colnames(X),                                                 # feature names
  !!!setNames(as.data.frame(round(pmd_builtin$v, 4)), paste0("BuiltIn_V", 1:K)), # built-in V
  !!!setNames(as.data.frame(round(pmd_manual$v, 4)),  paste0("Manual_V",  1:K))  # manual V
)

top_loadings <- function(v, feature_names, k = 10) {                     # top loadings helper
  tibble(Feature = feature_names, Loading = v) %>%                       # build table
    mutate(abs_loading = abs(Loading)) %>%                               # add abs loading
    arrange(desc(abs_loading)) %>%                                       # sort
    slice_head(n = k) %>%                                                # keep top k
    select(Feature, Loading)                                             # select columns
}

TopV_df <- bind_rows(lapply(seq_len(K), function(j) {                    # top-V per component
  out_b <- top_loadings(pmd_builtin$v[, j], colnames(X), k = 10) %>%      # built-in top
    rename(BuiltIn = Loading)                                            # rename col
  out_m <- top_loadings(pmd_manual$v[, j], colnames(X), k = 10) %>%       # manual top
    rename(Manual = Loading)                                             # rename col

  full_join(out_b, out_m, by = "Feature") %>%                            # merge by feature
    mutate(Component = paste0("V", j)) %>%                               # add component id
    relocate(Component)                                                  # move component first
})) %>%
  arrange(Component)                                                     # order components

D_df <- tibble(                                                          # D comparison table
  Component = paste0("Component ", 1:K),                                 # component labels
  BuiltIn_D = round(pmd_builtin$d, 6),                                   # built-in D
  Manual_D  = round(pmd_manual$d, 6),                                    # manual D
  AbsDiff   = round(abs(pmd_builtin$d - pmd_manual$d), 6)                # absolute diff
)

max_abs_v_diff <- max(abs(pmd_builtin$v - pmd_manual$v))                 # max V diff
max_abs_d_diff <- max(abs(pmd_builtin$d - pmd_manual$d))                 # max D diff
cat(sprintf("Max |V_builtin - V_manual| = %.6g\n", max_abs_v_diff))       # print V diff
cat(sprintf("Max |D_builtin - D_manual| = %.6g\n\n", max_abs_d_diff))     # print D diff

writeLines(                                                              # write V_df LaTeX
  capture.output(print(
    xtable(V_df,
           caption = "Right singular vectors (V): built-in PMD vs manual MFPMD.",
           label   = "tab:pmd_v_compare"),
    include.rownames = FALSE, comment = FALSE, sanitize.text.function = identity
  )),
  con = file.path(out_dir, "PMD_V_comparison.tex")                        # output file
)

writeLines(                                                              # write D_df LaTeX
  capture.output(print(
    xtable(D_df,
           caption = "Singular values (D): built-in PMD vs manual MFPMD.",
           label   = "tab:pmd_d_compare"),
    include.rownames = FALSE, comment = FALSE, sanitize.text.function = identity
  )),
  con = file.path(out_dir, "PMD_D_comparison.tex")                        # output file
)

writeLines(                                                              # write TopV_df LaTeX
  capture.output(print(
    xtable(TopV_df,
           caption = "Top absolute loadings per component (V): built-in PMD vs manual MFPMD.",
           label   = "tab:pmd_top_v_compare"),
    include.rownames = FALSE, comment = FALSE, sanitize.text.function = identity
  )),
  con = file.path(out_dir, "PMD_TopV_comparison.tex")                     # output file
)

V_long <- tibble(                                                         # long format V
  Feature   = rep(colnames(X), times = K),                                 # feature names
  Component = factor(rep(paste0("V", 1:K), each = p), levels = paste0("V", 1:K)), # component factor
  BuiltIn   = as.vector(pmd_builtin$v),                                    # built-in loadings
  Manual    = as.vector(pmd_manual$v)                                      # manual loadings
)

p_scatter <- ggplot(V_long, aes(x = BuiltIn, y = Manual)) +                # scatter plot
  geom_hline(yintercept = 0, linewidth = 0.25, linetype = 2) +            # y=0 line
  geom_vline(xintercept = 0, linewidth = 0.25, linetype = 2) +            # x=0 line
  geom_point(alpha = 0.8, size = 1.6) +                                   # points
  geom_abline(intercept = 0, slope = 1, linewidth = 0.35) +               # 45-degree line
  facet_wrap(~ Component, nrow = 1) +                                     # facet by component
  labs(x = "Built-in PMD loading", y = "Manual MFPMD loading") +          # axis labels
  theme_bw(base_size = 11)                                                # base theme

ggsave(                                                                    # save scatter PNG
  filename = file.path(out_dir, "PMD_V_scatter.png"),                      # output file
  plot     = p_scatter,                                                   # plot object
  width    = 12,                                                          # width in inches
  height   = 3.2,                                                         # height in inches
  units    = "in",                                                        # units
  dpi      = 450,                                                         # resolution
  bg       = "white"                                                      # background
)

cat("Exercise 7.2 outputs written to:\n")                                  # status line
cat(out_dir, "\n\n")                                                      # output path
cat("Files:\n")                                                            # files header
cat("- PMD_V_comparison.tex\n")                                            # file list
cat("- PMD_D_comparison.tex\n")                                            # file list
cat("- PMD_TopV_comparison.tex (recommended for paper)\n")                 # file list
cat("- PMD_V_scatter.png\n")                                               # file list

################################################################################
# END OF THE FILE!
################################################################################
