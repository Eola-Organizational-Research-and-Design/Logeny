

library(shiny)
library(reticulate)
library(DT)
library(dplyr)
library(stringr)
library(pdftools)
library(tidyr)
library(future)
library(furrr)
library(future.apply)

# Source Python scripts
source_python("zotero_integration.py")
source_python("classify_text.py")
source_python("neighborhood_search.py")

# Function to find existing Python installations
find_python <- function() {
  python_paths <- c(
    Sys.which("python"),
    Sys.which("python3"),
    Sys.getenv("PYTHON"),
    Sys.getenv("PYTHON3")
  )
  python_paths <- unique(python_paths[python_paths != ""]) # Remove empty paths
  return(python_paths)
}

python_paths <- find_python()

if (length(python_paths) > 0 && python_paths[1] != "") {
  message("Using existing Python installation at: ", python_paths[1])
  reticulate::use_python(python_paths[1], required = TRUE)
} else {
  if (!"r-miniconda" %in% reticulate::conda_list()$name) {
    message("No Python installation found. Installing Miniconda...")
    reticulate::install_miniconda()
  }
  reticulate::use_condaenv("r-miniconda", conda = "auto", required = TRUE)
}

# Install missing Python packages
required_packages <- c("requests", "beautifulsoup4", "numpy", "transformers", "torch", "pandas", "openai")
installed_packages <- reticulate::py_list_packages()$package
for (pkg in required_packages) {
  if (!pkg %in% installed_packages) {
    message(paste("Installing Python package:", pkg))
    reticulate::py_install(pkg)
  }
}

# PDF Context Extraction Function
extract_data_from_pdf <- function(pdf_path, search_terms, n) {
  pages <- pdf_text(pdf_path)
  content_full <- tolower(paste(pages, collapse = " "))
  doc_title <- basename(pdf_path)
  content_words <- unlist(str_split(content_full, "\\s+"))
  
  matched_snippets <- list()
  matched_words <- list()
  
  for (term in search_terms) {
    term_lc <- tolower(term)
    term_indices <- which(str_detect(content_words, fixed(term_lc, ignore_case = TRUE)))
    
    if (length(term_indices) > 0) {
      for (idx in term_indices) {
        start <- max(1, idx - n)
        end <- min(length(content_words), idx + n)
        snippet <- paste(content_words[start:end], collapse = " ")
        matched_snippets <- append(matched_snippets, snippet)
        matched_words <- append(matched_words, term)
      }
    }
  }
  
  if (length(matched_snippets) == 0) {
    return(data.frame(
      Document = character(0),
      Matched_Word = character(0),
      Context = character(0),
      stringsAsFactors = FALSE
    ))
  }
  
  data.frame(
    Document = rep(doc_title, length(matched_snippets)),
    Matched_Word = matched_words,
    Context = matched_snippets,
    stringsAsFactors = FALSE
  )
}

# Shiny UI
ui <- fluidPage(
  titlePanel("Pamplin COT Lab: Text-To-Columns"),
  sidebarLayout(
    sidebarPanel(
      textInput("zotero_db", "Path to zotero.sqlite", value = "/Users/shailshah/Zotero/zotero.sqlite"),
      textInput("zotero_dir", "Path to Zotero 'storage' Directory", value = "/Users/shailshah/Zotero/storage"),
      actionButton("load_collections", "Load Collections"),
      selectInput("collection_name", "Select a Collection", choices = c(), selected = NULL),
      actionButton("show_items", "Show Items in Collection"),
      br(), br(),
      textInput("search_terms", "Search Terms (comma-separated)", value = "differentiation, competition, competitor, strategy"),
      numericInput("context_n", "Context Words (n)", value = 50, min = 1, step = 1),
      actionButton("process_pdfs", "Process PDFs"),
      br(), textOutput("process_status"),
      textInput("doi_input", "Enter DOI of exemplar paper"),
      numericInput("n_input", "Enter n for n-neighborhood", value = 2, min = 1),
      actionButton("search_button", "Perform n-neighborhood search"),
      checkboxInput("add_to_collection", "Add search results to selected Zotero collection", value = TRUE),
      textOutput("neighborhood_status")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Items in Collection", DTOutput("items_table")),
        tabPanel("Search Results", DTOutput("snippets_table")),
        tabPanel("n-Neighborhood Search", DTOutput("neighborhood_table"))
      )
    )
  )
)

# Server logic
server <- function(input, output, session) {
  collections_list <- reactiveVal(NULL)
  items_metadata <- reactiveVal(NULL)
  data_store <- reactiveVal(NULL)
  
  `%||%` <- function(a, b) if (!is.null(a)) a else b
  observeEvent(input$load_collections, {
    req(input$zotero_db)
    tryCatch({
      coll_names <- get_all_collections(db_path = input$zotero_db)
      if (!is.null(coll_names) && length(coll_names) > 0) {
        collections_list(coll_names)
        updateSelectInput(session, "collection_name", choices = coll_names)
      } else {
        showNotification("No collections found.", type = "warning")
      }
    }, error = function(e) {
      showNotification(paste("Error loading collections:", e$message), type = "error")
    })
  })
  
  `%||%` <- function(a, b) if (!is.null(a)) a else b  # Helper operator
  
  observeEvent(input$show_items, {
    req(input$zotero_db, input$collection_name)
    tryCatch({
      meta_list <- get_collection_items_metadata(
        db_path = input$zotero_db, collection_name = input$collection_name, require_attachment = FALSE
      )
      if (!is.null(meta_list) && length(meta_list) > 0) {
        df <- dplyr::bind_rows(lapply(meta_list, function(x) {
          data.frame(
            itemID = x[["itemID"]] %||% NA,
            title = x[["title"]] %||% "(No Title)",
            authors = x[["authors"]] %||% "(No Authors)",
            year = x[["year"]] %||% "(No Year)",
            key = x[["key"]] %||% "(No Folder)",
            stringsAsFactors = FALSE
          )
        }))
        items_metadata(df)
      } else {
        items_metadata(NULL)
      }
    }, error = function(e) {
      showNotification(paste("Error fetching item metadata:", e$message), type = "error")
    })
  })
  
  output$items_table <- renderDT({
    req(items_metadata())
    datatable(items_metadata(), options = list(pageLength = 10, autoWidth = TRUE))
  })
  
  observeEvent(input$process_pdfs, {
    req(items_metadata(), input$zotero_dir, input$search_terms)
    
    # DEBUG: Show Zotero storage path
    print(paste("📁 Zotero Directory:", input$zotero_dir))
    
    search_terms <- str_split(input$search_terms, ",\\s*")[[1]]
    valid_folders <- file.path(input$zotero_dir, items_metadata()$key)
    
    # DEBUG: Show folder paths it's trying to read from
    print("🔍 Looking in folders:")
    print(valid_folders)
    
    pdf_files <- unlist(lapply(valid_folders, function(folder) {
      list.files(folder, pattern = "\\.pdf$", full.names = TRUE)
    }))
    
    # DEBUG: Show PDF files found
    print("📄 PDF files found:")
    print(pdf_files)
    
    withProgress(message = "Processing PDFs", value = 0, {
      pdf_data_list <- lapply(pdf_files, function(pdf) {
        print(paste(" Processing:", pdf))  # DEBUG
        incProgress(1 / length(pdf_files))
        extract_data_from_pdf(pdf, search_terms, input$context_n)
      })
      pdf_data <- bind_rows(pdf_data_list)
      data_store(pdf_data)
    })
    
    # DEBUG: Show number of snippets
    print(paste("Total snippets found:", nrow(data_store())))
    
    output$process_status <- renderText(paste("Processing completed! Found", nrow(data_store()), "snippets."))
  })
  
  observeEvent(input$search_button, {
    req(input$doi_input, input$n_input)
    
    output$neighborhood_status <- renderText(" Starting search...")
    
    withProgress(message = "Running n-neighborhood search...", value = 0, {
      tryCatch({
        print(" Calling Python function: n_neighborhood_search")
        print(paste("DOI:", input$doi_input, "| Depth:", input$n_input))
        
        # Call Python function
        results <- n_neighborhood_search(input$doi_input, input$n_input)
        
        print("Python function completed")
        print(results)
        
        # Debug checkbox and collection state
        print(paste(" Checkbox state:", input$add_to_collection))
        print(paste(" Collection:", input$collection_name))
        
        # Handle saving results to Zotero
        if (isTRUE(input$add_to_collection) && nzchar(input$collection_name)) {
          print(" Preparing results for Zotero insert...")
          
          if (is.data.frame(results)) {
            results_list <- lapply(seq_len(nrow(results)), function(i) {
              list(
                title = results[i, "Title"] %||% "",
                authors = strsplit(results[i, "Authors"] %||% "", ";\\s*")[[1]],
                year = results[i, "Year"] %||% "",
                doi = results[i, "DOI"] %||% ""
              )
            })
            
            print(" Result list ready, adding to Zotero...")
            add_crossref_results_to_zotero(input$zotero_db, input$collection_name, results_list)
            output$neighborhood_status <- renderText(" Added results to Zotero collection.")
          } else {
            showNotification("⚠️ Unexpected results format. Not a data.frame.", type = "error")
            print("⚠️ Results not a data.frame")
          }
        }
        
        # Show the results table
        output$neighborhood_table <- renderDT({
          datatable(as.data.frame(results), options = list(pageLength = 10, autoWidth = TRUE))
        })
        
        output$neighborhood_status <- renderText({
          paste0("Search completed! Found ", nrow(results), " papers.")
        })
        
      }, error = function(e) {
        print(paste(" ERROR in n-neighborhood search:", e$message))
        output$neighborhood_status <- renderText({
          paste0("Error: ", e$message)
        })
        showNotification(paste("Error in n-neighborhood search:", e$message), type = "error")
      })
    })
  })
}
# Run the app
shinyApp(ui = ui, server = server)
