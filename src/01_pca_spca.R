################################################################################
# ML II Group Assignment — The Beautiful Game (Reduced)
# Francesco Serra | Job Siegmann | Sadra Daneshvar
################################################################################

rm(list = ls())                                  # clear workspace

# =========================
# 0) Packages
# =========================
req_pkgs <- c("dplyr", "tidyr", "ggplot2", "tibble", "stringr", "forcats",  # required packages
              "PMA", "xtable", "scales", "ggrepel")                         # required packages
missing_pkgs <- req_pkgs[!req_pkgs %in% rownames(installed.packages())]     # find missing packages
if (length(missing_pkgs) > 0) {                                             # fail with setup guidance
  stop(sprintf(
    "Missing R packages: %s. From the repository root, run `make setup`.",
    paste(missing_pkgs, collapse = ", ")
  ), call. = FALSE)
}

library(dplyr)                                # data wrangling
library(tidyr)                                # data reshaping
library(ggplot2)                              # plotting
library(tibble)                               # tibbles
library(stringr)                              # string helpers
library(forcats)                              # factor helpers
library(PMA)                                  # SPCA/SPC tools
library(xtable)                               # LaTeX tables
library(scales)                               # axis/label helpers
library(ggrepel)                              # non-overlapping labels

# =========================
# 1) Paths + options
# =========================
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE) # Rscript path
repo_root <- if (length(script_arg) > 0) {       # derive root when run with Rscript
  script_path <- normalizePath(sub("^--file=", "", script_arg[1]), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
} else {
  normalizePath(getwd(), mustWork = TRUE)        # interactive fallback: run from repo root
}

data_path <- Sys.getenv(                         # private data can live outside Git
  "FIFA2017_NL_PATH",
  unset = file.path(repo_root, "data", "FIFA2017_NL.RData")
)

out_dir <- Sys.getenv(                           # generated artifacts stay outside source
  "FIFA_PCA_RESULTS_DIR",
  unset = file.path(repo_root, "results", "pca_spca")
)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)  # create output folder

if (!interactive()) grDevices::pdf(file = NULL) # suppress implicit Rplots.pdf in batch runs

save_figures <- TRUE                           # toggle saving figures
use_cairo <- FALSE                             # toggle Cairo usage

set.seed(1363)                                 # reproducibility seed

# =========================
# 2) Labels
# =========================
pretty_var <- function(x) {                    # prettify variable names
  x <- gsub("_", " ", x)                       # underscores to spaces
  x <- gsub("\\s+", " ", x)                    # collapse extra spaces
  x <- trimws(x)                               # trim whitespace
  tools::toTitleCase(x)                        # title case
}

# =========================
# 3) Plot theme
# =========================
font_family <- "sans"                          # portable plot font
theme_academic <- function(base_size = 12) {   # reusable ggplot theme
  theme_bw(base_size = base_size, base_family = font_family) +              # base theme
    theme(
      panel.grid.major = element_line(linewidth = 0.25),                    # light major grid
      panel.grid.minor = element_blank(),                                   # no minor grid

      legend.title = element_text(size = base_size + 1),                    # legend title size
      legend.text  = element_text(size = base_size),                        # legend text size
      legend.key.size = unit(0.85, "cm"),                                   # legend key size
      legend.spacing.y = unit(0.15, "cm"),                                  # legend vertical spacing
      legend.spacing.x = unit(0.20, "cm"),                                  # legend horizontal spacing

      axis.title = element_text(size = base_size),                          # axis title size
      axis.text  = element_text(size = base_size - 1),                      # axis text size
      plot.title = element_blank()                                          # remove titles
    )
}

pal_value <- c("Q1 (low)"  = "#56B4E9",        # value quartile palette
               "Q2"       = "#009E73",         # value quartile palette
               "Q3"       = "#E69F00",         # value quartile palette
               "Q4 (high)"= "#D55E00")         # value quartile palette

pal_pos <- c("Keeper"     = "#0072B2",         # position palette
             "Defense"    = "#009E73",         # position palette
             "Midfielder" = "#E69F00",         # position palette
             "Attack"     = "#D55E00")         # position palette

# =========================
# 4) Save plots (PNG)
# =========================
save_plot_png <- function(p, filename, width = 10, height = 6, dpi = 1000) { # save helper
  if (!save_figures) return(invisible(NULL))                                 # skip if off
  path <- file.path(out_dir, filename)                                       # full output path

  ggsave(                                                                    # write file
    filename = path,                                                         # output file
    plot     = p,                                                            # ggplot object
    width    = width,                                                        # width in inches
    height   = height,                                                       # height in inches
    units    = "in",                                                         # units
    dpi      = dpi,                                                          # resolution
    bg       = "white",                                                      # white background
    device   = "png"                                                         # PNG device
  )
}

# =========================
# 5) LaTeX tables
# =========================
print_tex_table <- function(df, caption, label, file, digits = NULL) {       # LaTeX table helper
  xt <- xtable(df, caption = caption, label = label, digits = digits)        # make xtable
  tex <- capture.output(                                                     # capture LaTeX
    print(
      xt,                                                                    # xtable object
      include.rownames = FALSE,                                              # no row names
      sanitize.text.function = identity,                                     # keep LaTeX
      floating = TRUE,                                                       # floating table
      comment = FALSE                                                        # no % comments
    )
  )
  cat(paste(tex, collapse = "\n"), "\n\n")                                   # print to console
  writeLines(tex, con = file.path(out_dir, file))                            # write to file
  invisible(tex)                                                             # return invisibly
}

# =========================
# 6) Summary stats table
# =========================
make_summary_stats <- function(df, vars, label_map) {                        # summary stats helper
  summ <- tibble(var = vars) %>%                                             # start table
    mutate(
      N    = sapply(vars, function(v) sum(!is.na(df[[v]]))),                 # non-missing N
      Mean = sapply(vars, function(v) mean(df[[v]], na.rm = TRUE)),          # mean
      SD   = sapply(vars, function(v) sd(df[[v]], na.rm = TRUE))             # sd
    ) %>%
    mutate(Variable = unname(label_map[var])) %>%                            # add labels
    select(Variable, N, Mean, SD)                                            # select columns

  m <- nrow(summ)                                                            # number of rows
  left  <- summ[1:ceiling(m/2), ]                                            # left block
  right <- summ[(ceiling(m/2)+1):m, ]                                        # right block
  if (nrow(right) < nrow(left)) {                                            # pad if needed
    right <- bind_rows(right, tibble(Variable = NA, N = NA, Mean = NA, SD = NA)) # pad row
  }

  out <- bind_cols(                                                          # join blocks
    left,                                                                    # left side
    right %>% rename(Variable_2 = Variable, N_2 = N, Mean_2 = Mean, SD_2 = SD) # right side
  )

  colnames(out) <- c("Variable", "N", "Mean", "St. Dev.",                    # set column names
                     "Variable", "N", "Mean", "St. Dev.")                   # set column names
  out                                                                         # return table
}

# =========================
# 7) Top-k loadings table
# =========================
topk_loadings_side_by_side <- function(L, label_map, k = 5, digits = 3, drop_zeros = FALSE) { # top-k helper
  L <- as.matrix(L)                                                          # ensure matrix
  comps <- colnames(L)                                                       # component names
  if (is.null(comps)) comps <- paste0("C", seq_len(ncol(L)))                 # default names

  get_top <- function(j) {                                                   # per-component extractor
    x <- L[, j]                                                              # loadings vector
    if (drop_zeros) {                                                        # optionally drop zeros
      idx_nz <- which(abs(x) > 0)                                            # non-zero indices
      x2 <- x[idx_nz]                                                        # non-zero loadings
      if (length(x2) == 0) {                                                 # handle all-zero
        return(tibble(Variable = rep(NA, k), Loading = rep(NA, k)))           # return NA block
      }
      ord <- order(abs(x2), decreasing = TRUE)                               # sort by abs
      pick <- idx_nz[ord][seq_len(min(k, length(ord)))]                      # pick top k
    } else {
      ord <- order(abs(x), decreasing = TRUE)                                # sort by abs
      pick <- ord[seq_len(min(k, length(ord)))]                              # pick top k
    }
    tibble(
      Variable = unname(label_map[names(x)[pick]]),                          # variable labels
      Loading  = round(x[pick], digits)                                      # rounded loading
    ) %>%
      { if (nrow(.) < k) bind_rows(., tibble(Variable = rep(NA, k - nrow(.)), Loading = rep(NA, k - nrow(.)))) else . } # pad to k
  }

  blocks <- lapply(seq_len(ncol(L)), get_top)                                # get blocks per comp
  names(blocks) <- comps                                                     # name blocks

  out <- do.call(cbind, blocks)                                              # bind side-by-side
  out                                                                         # return table
}

# =========================
# 8) Load data
# =========================
if (!file.exists(data_path)) {                    # actionable data-contract failure
  stop(paste0(
    "Dataset not found at `", data_path, "`. ",
    "See data/README.md and set FIFA2017_NL_PATH to your authorized copy."
  ), call. = FALSE)
}
load(data_path)                                   # load .RData
stopifnot(exists("fifa"))                         # check object exists

fifa_raw <- fifa                                  # keep raw copy

pos_col <- if ("Position" %in% names(fifa_raw)) "Position" else if ("position" %in% names(fifa_raw)) "position" else NA_character_ # position col
stopifnot(!is.na(pos_col))                        # require position col

econ_candidates <- c("eur_value", "eur_wage", "eur_release_clause")           # candidate econ vars
econ_vars <- econ_candidates[econ_candidates %in% names(fifa_raw)]            # existing econ vars
stopifnot(length(econ_vars) >= 1)                                             # need at least one

num_cols <- names(fifa_raw)[sapply(fifa_raw, is.numeric)]                     # numeric columns

skill_vars0 <- setdiff(num_cols, econ_vars)                                   # numeric non-econ vars
skill_vars_0_100 <- skill_vars0[sapply(fifa_raw[skill_vars0], function(z) {   # candidate 0-100 skills
  z <- z[!is.na(z)]                                                           # drop NA
  if (length(z) == 0) return(FALSE)                                           # skip empty
  all(z >= 0 & z <= 100)                                                      # check bounds
})]

skill_vars <- if (length(skill_vars_0_100) >= 20) skill_vars_0_100 else skill_vars0 # choose skills set

need_cols <- unique(c(skill_vars, econ_vars, pos_col))                        # required columns
fifa <- fifa_raw %>%                                                          # start data
  filter(if_all(all_of(need_cols), ~ !is.na(.)))                              # complete cases

label_map <- setNames(pretty_var(names(fifa)), names(fifa))                   # variable label map

value_q <- ntile(fifa$eur_value, 4)                                           # value quartile index
value_q_lab <- factor(value_q, levels = 1:4,                                  # quartile factor
                      labels = c("Q1 (low)", "Q2", "Q3", "Q4 (high)"))         # quartile labels

pos_clean <- toupper(trimws(as.character(fifa[[pos_col]])))                   # clean position strings
pos_group <- case_when(                                                       # map to 4 groups
  pos_clean == "GK"  ~ "Keeper",                                              # GK -> Keeper
  pos_clean == "DEF" ~ "Defense",                                             # DEF -> Defense
  pos_clean == "MID" ~ "Midfielder",                                          # MID -> Midfielder
  pos_clean == "FW"  ~ "Attack",                                              # FW -> Attack
  TRUE ~ NA_character_                                                        # unknown -> NA
) %>%
  factor(levels = c("Keeper", "Defense", "Midfielder", "Attack"))             # set order

keep_idx <- !is.na(pos_group)                                                 # keep known groups
fifa <- fifa[keep_idx, ]                                                      # subset fifa
value_q_lab <- value_q_lab[keep_idx]                                          # subset quartiles
pos_group <- droplevels(pos_group[keep_idx])                                  # drop unused levels

X_skills <- fifa %>% select(all_of(skill_vars)) %>% as.data.frame()           # skills matrix

# =========================
# 9) Summary statistics
# =========================
vars_for_table <- c(skill_vars, econ_vars)                                    # table vars
summ_tbl <- make_summary_stats(fifa, vars_for_table, label_map)               # build summary table

digits_fix <- function(df, digits_no_rownames, rownames_digits = 0) {         # xtable digits helper
  need <- ncol(df) + 1                                                        # required length
  out  <- c(rownames_digits, digits_no_rownames)                              # prepend rownames digit
  if (length(out) < need) out <- c(out, rep(tail(out, 1), need - length(out)))# pad to length
  if (length(out) > need) out <- out[1:need]                                  # trim to length
  out                                                                         # return vector
}

print_tex_table(                                                               # export summary LaTeX
  df      = summ_tbl,                                                          # data
  caption = "Summary Statistics",                                              # caption
  label   = "tab:summarystats",                                                # label
  file    = "summarystats.tex",                                                # output file
  digits  = digits_fix(summ_tbl, c(0, 0, 0, 2, 2, 0, 2, 2))                    # digits vector
)

# =========================
# 10) PCA + PVE
# =========================
pca <- prcomp(X_skills, center = TRUE, scale. = TRUE)                         # fit PCA

pve <- (pca$sdev^2) / sum(pca$sdev^2)                                         # PVE by PC
cum_pve <- cumsum(pve)                                                        # cumulative PVE

pve_tbl <- tibble(                                                            # PVE table
  Component = paste0("PC", seq_along(pve)),                                   # PC labels
  PVE = pve,                                                                   # PVE
  CumPVE = cum_pve                                                             # cumulative
)

cat(sprintf("PCA PVE: PC1 = %.1f%%, PC2 = %.1f%%, Cum(1:2) = %.1f%%\n\n",      # print key PVE
            100*pve[1], 100*pve[2], 100*sum(pve[1:2])))                       # PVE values

K <- min(15, nrow(pve_tbl))                                                   # max PCs shown

df_scree <- pve_tbl %>%                                                       # scree data
  slice(1:K) %>%                                                               # keep first K
  mutate(
    k = row_number(),                                                          # PC index
    CumPVE = cumsum(PVE)                                                       # recompute cum
  )

PVE_max <- max(df_scree$PVE)                                                  # max PVE (scale)
Cum_max <- max(df_scree$CumPVE)                                               # max cum (scale)

cum_breaks <- seq(0, 1, by = 0.2)                                             # cum axis breaks
cum_labels <- paste0(100 * cum_breaks, "%")                                   # cum axis labels

p_scree <- ggplot(df_scree, aes(x = k)) +                                     # base scree plot
  geom_col(aes(y = PVE), width = 0.75, fill = "#2C7FB8", alpha = 0.85) +      # PVE bars
  geom_line(aes(y = PVE, group = 1), linewidth = 0.6, color = "#0B3C5D") +    # PVE line
  geom_point(aes(y = PVE), size = 2.0, color = "#0B3C5D") +                   # PVE points
  geom_line(aes(y = (CumPVE / Cum_max) * PVE_max, group = 1), linewidth = 0.75, color = "#D95F02") + # cum line (scaled)
  geom_point(aes(y = (CumPVE / Cum_max) * PVE_max), size = 1.8, color = "#D95F02") +                 # cum points (scaled)
  geom_hline(yintercept = (0.80 / Cum_max) * PVE_max, linetype = "dashed", linewidth = 0.5, color = "grey40") +           # 80% line
  annotate("text", x = K, y = (0.80 / Cum_max) * PVE_max, label = "80% cumulative", hjust = 1.02, vjust = -0.4, size = 3.2, color = "grey30") + # 80% label
  scale_x_continuous(breaks = 1:K) +                                          # x ticks
  scale_y_continuous(                                                         # y + secondary axis
    name = "Proportion of Variance Explained",                                # y label
    labels = percent_format(accuracy = 1),                                    # y format
    sec.axis = sec_axis(
      transform = ~ (. / PVE_max) * Cum_max,                                 # back-transform
      name   = "Cumulative Variance Explained",                               # sec label
      breaks = cum_breaks * Cum_max,                                          # sec breaks
      labels = cum_labels                                                     # sec labels
    )
  ) +
  labs(x = "Component") +                                                     # x label
  theme_academic() +                                                          # theme
  theme(legend.position = "none", panel.grid.minor = element_blank())         # final tweaks

print(p_scree)                                                                 # show plot
save_plot_png(p_scree, "PCA_scree.png", width = 8, height = 5, dpi = 600)      # save plot

# =========================
# 11) PCA plots
# =========================
scores_pca <- as.data.frame(pca$x[, 1:2, drop = FALSE]) %>%                    # PC scores (1-2)
  mutate(
    value_q = value_q_lab,                                                     # add value quartile
    pos     = pos_group,                                                       # add position group
    log_value = log1p(fifa$eur_value)                                          # log value
  )

cat(sprintf("Corr(PC1, log(1+eur_value)) = %.3f\n\n",                          # print correlation
            cor(scores_pca$PC1, scores_pca$log_value, use = "complete.obs")))  # correlation value

p_pca_val <- ggplot(scores_pca, aes(x = PC1, y = PC2, color = value_q)) +      # PCA scores by value
  geom_hline(yintercept = 0, linetype = 2, linewidth = 0.4) +                 # y=0 line
  geom_vline(xintercept = 0, linetype = 2, linewidth = 0.4) +                 # x=0 line
  geom_point(alpha = 0.85, size = 2.0) +                                      # points
  scale_color_manual(values = pal_value) +                                    # colors
  labs(x = "PC1 score", y = "PC2 score", color = "Value quartile") +          # labels
  theme_academic()                                                             # theme

print(p_pca_val)                                                               # show plot
save_plot_png(p_pca_val, "PCA_scores_valuequartile.png", width = 8.5, height = 5.5, dpi = 600) # save plot

p_pca_pos <- ggplot(scores_pca, aes(x = PC1, y = PC2, color = pos)) +          # PCA scores by position
  geom_hline(yintercept = 0, linetype = 2, linewidth = 0.4) +                 # y=0 line
  geom_vline(xintercept = 0, linetype = 2, linewidth = 0.4) +                 # x=0 line
  geom_point(alpha = 0.85, size = 2.0) +                                      # points
  scale_color_manual(values = pal_pos) +                                      # colors
  labs(x = "PC1 score", y = "PC2 score", color = "Position group") +          # labels
  theme_academic()                                                             # theme

print(p_pca_pos)                                                               # show plot
save_plot_png(p_pca_pos, "PCA_scores_position.png", width = 8.5, height = 5.5, dpi = 600) # save plot

load_pca <- as.data.frame(pca$rotation[, 1:2, drop = FALSE]) %>%               # loadings (1-2)
  rownames_to_column("var") %>%                                               # keep variable names
  mutate(label = unname(label_map[var]))                                       # add pretty labels

p_load <- ggplot(load_pca, aes(x = PC1, y = PC2)) +                            # loadings scatter
  geom_hline(yintercept = 0, linetype = 2, linewidth = 0.4) +                 # y=0 line
  geom_vline(xintercept = 0, linetype = 2, linewidth = 0.4) +                 # x=0 line
  geom_point(size = 1.6, alpha = 0.8) +                                       # points
  ggrepel::geom_text_repel(aes(label = label), size = 3, max.overlaps = 60) + # labels
  labs(x = "Loading on PC1", y = "Loading on PC2") +                          # labels
  theme_academic()                                                             # theme

print(p_load)                                                                  # show plot
save_plot_png(p_load, "PCA_loadings_PC1_PC2.png", width = 8.5, height = 6, dpi = 600) # save plot

scale_fac <- 0.8 * min(                                                        # biplot scale factor
  diff(range(scores_pca$PC1)) / diff(range(load_pca$PC1)),                     # scale PC1
  diff(range(scores_pca$PC2)) / diff(range(load_pca$PC2))                      # scale PC2
)

load_bi <- load_pca %>%                                                        # scaled loadings for biplot
  mutate(PC1s = PC1 * scale_fac, PC2s = PC2 * scale_fac)                       # apply scaling

p_biplot <- ggplot(scores_pca, aes(x = PC1, y = PC2)) +                        # biplot base (scores)
  geom_hline(yintercept = 0, linetype = 2, linewidth = 0.4) +                 # y=0 line
  geom_vline(xintercept = 0, linetype = 2, linewidth = 0.4) +                 # x=0 line
  geom_point(color = "grey40", alpha = 0.55, size = 1.7) +                    # score points
  geom_segment(
    data = load_bi,                                                            # loadings data
    aes(x = 0, y = 0, xend = PC1s, yend = PC2s),                                # arrows from origin
    linewidth = 0.35,                                                          # line width
    arrow = arrow(length = unit(0.15, "cm")),                                  # arrow head
    color = "#D55E00"                                                          # arrow color
  ) +
  ggrepel::geom_text_repel(
    data = load_bi,                                                            # loadings data
    aes(x = PC1s, y = PC2s, label = label),                                     # label positions
    size = 2.8,                                                                # label size
    color = "#D55E00",                                                         # label color
    max.overlaps = 60                                                          # overlap cap
  ) +
  labs(x = "PC1 score", y = "PC2 score") +                                     # axis labels
  theme_academic()                                                              # theme

print(p_biplot)                                                                 # show plot
save_plot_png(p_biplot, "PCA_biplot.png", width = 10.5, height = 8.0, dpi = 600) # save plot

# =========================
# 12) PCA top-5 loadings
# =========================
pca_top5 <- topk_loadings_side_by_side(                                        # compute top-5 table
  L = pca$rotation[, 1:2, drop = FALSE],                                       # PC1-2 loadings
  label_map = label_map,                                                       # label map
  k = 5,                                                                       # top k
  digits = 2,                                                                  # rounding
  drop_zeros = FALSE                                                           # keep zeros
)

print_tex_table(                                                                # export PCA loadings table
  df      = pca_top5,                                                          # data
  caption = "Top 5 absolute loadings for PC1 and PC2 (PCA).",                  # caption
  label   = "tab:pca_top5_loadings",                                           # label
  file    = "PCA_top5_loadings.tex"                                            # output file
)

# =========================
# 13) SPCA + robustness
# =========================
X_std <- scale(X_skills)                                                       # standardize skills

K <- 2                                                                         # number of components
sumabs_list <- c(2.0, 1.5, 2.5)                                                 # sparsity targets

run_spca_and_export <- function(sumabs) {                                      # SPCA runner
  spca <- SPC(X_std, sumabs = sumabs, K = K, center = FALSE, trace = FALSE)   # fit SPCA

  scores_spca <- as.data.frame(X_std %*% spca$v)                               # SPCA scores
  colnames(scores_spca) <- c("SPC1", "SPC2")                                   # score names

  scores_spca <- scores_spca %>%                                               # add groups
    mutate(
      value_q = value_q_lab,                                                   # value quartile
      pos     = pos_group                                                      # position group
    )

  p_val <- ggplot(scores_spca, aes(x = SPC1, y = SPC2, color = value_q)) +     # SPCA by value
    geom_hline(yintercept = 0, linetype = 2, linewidth = 0.4) +               # y=0 line
    geom_vline(xintercept = 0, linetype = 2, linewidth = 0.4) +               # x=0 line
    geom_point(alpha = 0.85, size = 2.0) +                                    # points
    scale_color_manual(values = pal_value) +                                  # colors
    labs(x = "SPC1 score", y = "SPC2 score", color = "Value quartile") +      # labels
    theme_academic()                                                           # theme

  p_pos <- ggplot(scores_spca, aes(x = SPC1, y = SPC2, color = pos)) +         # SPCA by position
    geom_hline(yintercept = 0, linetype = 2, linewidth = 0.4) +               # y=0 line
    geom_vline(xintercept = 0, linetype = 2, linewidth = 0.4) +               # x=0 line
    geom_point(alpha = 0.85, size = 2.0) +                                    # points
    scale_color_manual(values = pal_pos) +                                    # colors
    labs(x = "SPC1 score", y = "SPC2 score", color = "Position group") +      # labels
    theme_academic()                                                           # theme

  print(p_val)                                                                 # show plot
  print(p_pos)                                                                 # show plot

  if (abs(sumabs - 2.0) < 1e-9) {                                              # main spec files
    save_plot_png(p_val, "SPCA_scores_valuequartile.png", width = 8.5, height = 5.5, dpi = 600) # save
    save_plot_png(p_pos, "SPCA_scores_position.png", width = 8.5, height = 5.5, dpi = 600)      # save
    file_tbl <- "SPCA_top5_loadings.tex"                                       # table filename
    label_tbl <- "tab:spca_top5_loadings"                                      # table label
  } else {                                                                     # robustness files
    s_tag <- gsub("\\.", "p", sprintf("%.1f", sumabs))                         # tag for filenames
    save_plot_png(p_val, paste0("SPCA_scores_valuequartile_sumabs", s_tag, ".png"), width = 8.5, height = 5.5, dpi = 600) # save
    save_plot_png(p_pos, paste0("SPCA_scores_position_sumabs", s_tag, ".png"), width = 8.5, height = 5.5, dpi = 600)      # save
    file_tbl <- paste0("SPCA_top5_loadings_sumabs", s_tag, ".tex")             # table filename
    label_tbl <- paste0("tab:spca_top5_loadings_sumabs", s_tag)                # table label
  }

  v <- spca$v[, 1:2, drop = FALSE]                                             # keep first 2 loadings
  rownames(v) <- rownames(v) %||% colnames(X_skills)                           # set rownames

  spca_top5 <- topk_loadings_side_by_side(                                     # compute top-5 table
    L = v,                                                                     # loadings
    label_map = label_map,                                                     # label map
    k = 5,                                                                     # top k
    digits = 2,                                                                # rounding
    drop_zeros = TRUE                                                          # drop zeros
  )

  print_tex_table(                                                              # export SPCA table
    df      = spca_top5,                                                       # data
    caption = "Top 5 absolute loadings for SPC1 and SPC2 (SPCA).",             # caption
    label   = label_tbl,                                                       # label
    file    = file_tbl                                                         # output file
  )

  invisible(list(spca = spca, scores = scores_spca))                           # return results
}

spca_results <- lapply(sumabs_list, run_spca_and_export)                       # run all sumabs

cat("Done. Files written to:\n")                                               # status line
cat(out_dir, "\n")                                                             # output path
cat("Key report figures saved as PNG:\n",                                      # list figures
    "- PCA_scree.png\n",
    "- PCA_scores_valuequartile.png\n",
    "- PCA_scores_position.png\n",
    "- PCA_loadings_PC1_PC2.png\n",
    "- PCA_biplot.png\n",
    "- SPCA_scores_valuequartile.png\n",
    "- SPCA_scores_position.png\n",
    "Robustness figures saved with *_sumabs1p5 / *_sumabs2p5 suffix.\n", sep = "") # robustness note

################################################################################
# END OF THE FILE!
################################################################################
