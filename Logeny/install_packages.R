# Get the user library path from the environment variable
R_LIBS_USER <- Sys.getenv('R_LIBS_USER')

# Create the user library directory if it doesn't exist
if (!dir.exists(R_LIBS_USER)) {
  dir.create(R_LIBS_USER, recursive = TRUE)
}

# List of R packages to install
r_packages_to_install <- c('shiny', 'reticulate', 'DT', 'dplyr', 'stringr', 'tools', 'DBI', 'RSQLite', 'digest', 'shinyjs', 'purrr', 'commonmark', 'htmltools', 'jsonlite', 'later')

# Loop through the R packages and install if not already present
for (pkg in r_packages_to_install) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, lib = R_LIBS_USER, repos = 'https://cloud.r-project.org/')
  }
}

cat("Required R packages should now be installed or already present.\n")



