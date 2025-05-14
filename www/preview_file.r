library(shiny)
library(reticulate)
library(DT)
library(dplyr)
library(stringr)
library(tools)
library(DBI)
library(RSQLite)
library(digest)

# Python dependencies
required_packages <- c(
  "requests", "safetensors", "beautifulsoup4", "numpy", "inflect",
  "transformers", "torch", "pandas", "PyPDF2", "python-docx", "nltk", "python-pptx","docx",
  "openai", "sentence_transformers", "accelerate>=0.26.0"
)
for (pkg in required_packages) {
  if (!reticulate::py_module_available(pkg)) {
    message("Installing Python package: ", pkg)
    reticulate::py_install(pkg)
  }
}
py_run_string("import nltk; nltk.download('wordnet', quiet=True)")

# Source Python files
source_python("zotero_integration.py")
source_python("vector_db_search.py")
source_python("user_auth.py")

# UI
ui <- fluidPage(
  titlePanel("EOLA ORD: Secure Vector DB + Projects"),
  uiOutput("main_ui")
)

# Server
server <- function(input, output, session) {
  db_path <- reactiveVal(NULL)
  current_user <- reactiveVal(NULL)
  project_note_data <- reactiveVal(NULL)
  data_store <- reactiveVal(NULL)
  items_metadata <- reactiveVal(NULL)
  selected_file <- reactiveVal(NULL)
  
  
  
  
  # Dynamic UI
  output$main_ui <- renderUI({
    if (is.null(current_user())) {
      fluidRow(
        column(6, offset = 1,
               wellPanel(
                 h4("Enter Project Folder:"),
                 textInput("db_folder", NULL, value = ""),
                 actionButton("db_connect", "Connect or Create DB"),
                 br(), br(),
                 uiOutput("auth_ui"),
                 textOutput("auth_status")
               ))
      )
    } else {
      tagList(
        h4(paste("Logged in as:", current_user()$username, "| Role:", current_user()$role)),
        tabsetPanel(
          tabPanel("Sync & Search",
                   actionButton("refresh_db", "Referesh DB"),
                   numericInput("chunk_size", "Chunk Size (# words)", value = 50, min = 5),
                   textInput("embedding_model", "Model Name", value = "sentence-transformers/all-MiniLM-L6-v2"),
                   actionButton("generate_embeddings", "Generate Embeddings"),
                   textOutput("status_text"),
                   textOutput("process_status")
          ),
          tabPanel("Collections", 
                    sidebarLayout(
                       sidebarPanel(
                         selectInput("collection_name", "Select a Collection", choices = c(), selected = NULL),
                         actionButton("show_items", "Show Items in Collection"),
                         actionButton("view_file", "View Selected File")
                          ),
                       mainPanel(DTOutput("items_table"))
                      )
                ),
          tabPanel("Search Collection",
                   sidebarLayout(
                       sidebarPanel(
                         textInput("vsearch_query", "Enter Search Term", value = ""),
                         numericInput("vsearch_topk", "Number of Results", value = 10, min = 1),
                         actionButton("run_vsearch", "Run Semantic Search")
                       ),
                       mainPanel(DTOutput("saved_snippets_table"))
                    )
                   ),
          tabPanel("Text Classification", textOutput("classification_status")),
          tabPanel("Q&A with GPT (Conversation)", verbatimTextOutput("conversation_history")),
          tabPanel("File Viewer", uiOutput("file_viewer")),
          tabPanel("Messages",
                   sidebarLayout(
                     sidebarPanel(
                       selectInput("msg_project_filter", "Filter by Project", choices = c("Global"), selected = "Global"),
                       textAreaInput("new_note", "New Note:", rows = 3),
                       actionButton("add_note", "Add Note"),
                       conditionalPanel(
                           condition = "output.user_is_admin == true",
                           h4("Pending User Requests"),
                           uiOutput("pending_users_ui")
                         )
                     ),
                     mainPanel(DTOutput("message_table"))
                   ),
 
                   textOutput("note_status")
                  )
        )
      )
    }
  })
  
  # DB Connection Logic
  observeEvent(input$db_connect, {
    req(input$db_folder)
    folder_path <- normalizePath(input$db_folder, mustWork = TRUE)
    dbfile <- file.path(folder_path, "folder_collection.sqlite")
    db_path(dbfile)
    
    if (!file.exists(dbfile)) {
      showModal(modalDialog(
        textInput("admin_username", "Enter Admin Username:"),
        passwordInput("admin_password", "Enter Admin Password:"),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("create_admin", "Create Admin")
        )
      ))

    } else {
      output$auth_ui <- renderUI({
        tagList(
          textInput("login_username", "Username:"),
          passwordInput("login_password", "Password:"),
          actionButton("login_btn", "Login"),
          br(),
          textInput("reg_username", "New Username:"),
          passwordInput("reg_password", "New Password:"),
          actionButton("register_btn", "Request Access")
        )
      })
    }
  })
  
  # Create Admin
  observeEvent(input$create_admin, {
    removeModal()
    req(input$db_folder)
    folder_path <- normalizePath(input$db_folder, mustWork = TRUE)
    dbfile <- file.path(folder_path, "folder_collection.sqlite")
    py$initialize_zotero_db_from_skeleton("skeleton.sqlite", dbfile)
    py$sync_folder_with_db(folder_path, dbfile)
    success <- py$create_admin_user(db_path(), input$admin_username, input$admin_password)
    if (success) {
      current_user(list(username = input$admin_username, role = "admin"))
      output$auth_status <- renderText("Admin user created. You're logged in.")
    } else {
      output$auth_status <- renderText("Admin creation failed.")
    }
  })
  
  # Login
  observeEvent(input$login_btn, {
    req(input$login_username, input$login_password, db_path())
    folder_path <- normalizePath(input$db_folder, mustWork = TRUE)
    dbfile <- file.path(folder_path, "folder_collection.sqlite")
    role <- py$authenticate_user(db_path(), input$login_username, input$login_password)
    if (!is.null(role)) {
      current_user(list(username = input$login_username, role = role))
      output$auth_status <- renderText(paste("Welcome", input$login_username))
      py$sync_folder_with_db(folder_path, dbfile)
      
      tryCatch({
        coll_names <- py$get_all_collections(db_path())
        coll_names <- c("All Documents", coll_names)
        updateSelectInput(session, "collection_name", choices=coll_names, selected="All Documents")
      }, error=function(e){
        message("Error loading collections: ", e$message)
      })
      
    } else {
      output$auth_status <- renderText("Invalid login or not yet approved.")
    }
  })
  
  # Register
  observeEvent(input$register_btn, {
    req(input$reg_username, input$reg_password, db_path())
    status <- py$register_user(db_path(), input$reg_username, input$reg_password, role = "member")
    if (status == "pending") {
      output$auth_status <- renderText("Registered! Awaiting admin approval.")
    } else {
      output$auth_status <- renderText("Registration failed: username exists or DB error.")
    }
  })
  
  # Re-load collections after DB is set
  observe({
    req(db_path())
    tryCatch({
      coll_names <- py$get_all_collections(db_path())
      coll_names <- c("All Documents", coll_names)
      updateSelectInput(session, "collection_name", choices=coll_names, selected="All Documents")
    }, error=function(e){
      message("Error loading collections: ", e$message)
    })
  })
  
  # Project Notes Tab
  observe({
    req(db_path(), current_user())
    project <- input$msg_project_filter
    tryCatch({
      con <- dbConnect(RSQLite::SQLite(), db_path())
      query <- "
      SELECT note, IFNULL(project_notes.created_by, 'system') AS created_by, created_at
      FROM project_notes 
      JOIN projects ON project_notes.project_id = projects.project_id
      WHERE projects.name = ?
      ORDER BY created_at DESC"
      df <- dbGetQuery(con, query, params = list(project))
      dbDisconnect(con)
      
      output$message_table <- renderDT({
        datatable(df, options=list(pageLength=5), rownames=FALSE)
      })
    }, error=function(e){
      output$message_table <- renderDT({
        datatable(data.frame(Note="Unable to load messages"))
      })
    })
    
    #manage pendeing users
    output$user_is_admin <- reactive({
      req(current_user())
      current_user()$role == "admin"
    })
    outputOptions(output, "user_is_admin", suspendWhenHidden = FALSE)
  })
  
  
  observe({
    req(current_user()$role == "admin", db_path())
    pending <- py$get_pending_users(db_path())
    
    if (length(pending) > 0) {
      output$pending_users_ui <- renderUI({
        tagList(
          lapply(pending, function(username) {
            fluidRow(
              column(6, strong(username)),
              column(3, actionButton(paste0("approve_", username), "Approve")),
              column(3, actionButton(paste0("reject_", username), "Reject"))
            )
          })
        )
      })
    } else {
      output$pending_users_ui <- renderUI({
        p("No pending users.")
      })
    }
  })
  
  # Observe dynamic approve/reject buttons
  observe({
    req(current_user()$role == "admin", db_path())
    pending <- py$get_pending_users(db_path())
    for (username in pending) {
      observeEvent(input[[paste0("approve_", username)]], {
        py$update_user_status(db_path(), username, "active")
        showNotification(paste("Approved user:", username), type = "message")
      })
      observeEvent(input[[paste0("reject_", username)]], {
        py$update_user_status(db_path(), username, "rejected")
        showNotification(paste("Rejected user:", username), type = "message")
      })
    }
  })
  
  
  # (A) Initialize DB
  observeEvent(input$refresh_db, {
    req(input$db_folder)
    folder_path <- normalizePath(input$db_folder, mustWork = TRUE)
    dbfile <- file.path(folder_path, "folder_collection.sqlite")
    db_path(dbfile)
    py$sync_folder_with_db(folder_path, dbfile)
    
    tryCatch({
      coll_names <- py$get_all_collections(db_path())
      coll_names <- c("All Documents", coll_names)
      updateSelectInput(session, "collection_name", choices=coll_names, selected="All Documents")
      showNotification(paste("Folder Synced"), type="message")
    }, error=function(e) {
      showNotification(paste("Error in folder sync:", e$message), type="error")
    })
  })
  
  # Re-load collections after DB is set
  observe({
    req(db_path())
    tryCatch({
      coll_names <- py$get_all_collections(db_path())
      coll_names <- c("All Documents", coll_names)
      updateSelectInput(session, "collection_name", choices=coll_names, selected="All Documents")
    }, error=function(e){
      message("Error loading collections: ", e$message)
    })
  })
  
  # (B) Generate embeddings
  observeEvent(input$generate_embeddings, {
    req(db_path())
    tryCatch({
      py$generate_document_embeddings(
        db_path(),
        chunk_size = as.integer(input$chunk_size),
        model_name = input$embedding_model
      )
      showNotification("Embeddings generated & stored in DB + .npy files!", type="message")
    }, error=function(e){
      showNotification(paste("Error generating embeddings:", e$message), type="error")
    })
  })
  
  # (C) Show Items
  observeEvent(input$show_items, {
    req(db_path(), input$collection_name)
    tryCatch({
      if (input$collection_name == "All Documents") {
        meta_list <- py$get_all_items(db_path())
      } else {
        meta_list <- py$get_collection_items_metadata(db_path(), input$collection_name, FALSE)
      }
      if (!is.null(meta_list) && length(meta_list)>0) {
        df_list <- lapply(meta_list, function(x){
          x[["title"]]   <- ifelse(is.null(x[["title"]])|| x[["title"]]=="","(No Title)", x[["title"]])
          x[["authors"]] <- ifelse(is.null(x[["authors"]])|| x[["authors"]]=="","(No Authors)",x[["authors"]])
          x[["year"]]    <- ifelse(is.null(x[["year"]])|| x[["year"]]=="","(No Year)",x[["year"]])
          x[["key"]]     <- ifelse(is.null(x[["key"]])|| x[["key"]]=="","(No Folder)",x[["key"]])

          as.data.frame(x, stringsAsFactors=FALSE)
        })
        df <- dplyr::bind_rows(df_list)
        items_metadata(df)
      } else {
        items_metadata(NULL)
      }
    }, error=function(e){
      showNotification(paste("Error fetching items:", e$message), type="error")
    })
  })
  
  output$items_table <- renderDT({
    df <- items_metadata()
    req(df)
    dt_select <- datatable(df, rownames=FALSE, selection = "single",
              options=list(pageLength=10, autoWidth=TRUE),
              colnames=c("Item ID","Title","Authors","Year","Folder Name"))
    dt_select
    
  })
  
  
  # (D) Vector Search
  observeEvent(input$run_vsearch, {
    req(db_path(), input$collection_name, input$vsearch_query)
    # call vector_db_search
    tryCatch({
      top_k <- as.integer(input$vsearch_topk)
      chunk_sz <- as.integer(input$chunk_size)
      model_nm <- input$embedding_model
      
      py$vector_db_search(
        db_path(),
        input$collection_name,
        input$vsearch_query,
        top_k,
        chunk_sz,
        model_nm
      )
      
      # Retrieve enriched results from the DB (with document name)
      df <- get_search_results(db_path(), collection_name = input$collection_name)
      if (nrow(df) == 0){
        showNotification("No vector-based matches found.", type = "warning")
        data_store(data.frame(Note = "No results from vector search."))
      } else {
        data_store(df)
      }
      
      
      
    }, error=function(e){
      showNotification(paste("Error in vector search:", e$message), type="error")
      data_store(data.frame(Note="Vector search error."))
    })
  })
  
  # (E) Show snippet results
    output$saved_snippets_table <- renderDT({
      df <- data_store()
      if (is.null(df) || nrow(df)==0) {
        return(datatable(data.frame(Note="No snippet results yet.")))
      }
      
      # Select only the columns you want to show
      df <- df[, c("document", "matched_word", "context")]
      
      datatable(df, rownames=FALSE, options=list(pageLength=10, autoWidth=TRUE))
    })
  
  
  # (F) Classification logic
  observe({
    req(data_store())
    tryCatch({
      column_names <- names(data_store())
      updateSelectInput(session, "text_column", choices=column_names, selected=column_names[1])
    }, error=function(e){
      message("Error updating classification columns:", e$message)
    })
  })
  
  observeEvent(input$run_classification, {
    req(data_store(), input$text_column, input$new_column,
        input$classification_prompt, input$classification_terms)
    
    dataset <- data_store()
    txt_col <- dataset[[input$text_column]]
    prompt  <- input$classification_prompt
    terms   <- str_split(input$classification_terms, ",\\s*")[[1]]
    withProgress(message="Running classification", value=0, {
      results <- future_map(txt_col, ~ classify_text(list(.x), prompt, terms), .progress=TRUE)
      dataset[[input$new_column]] <- unlist(results)
      data_store(dataset)
    })
    output$classification_status <- renderText("Classification done!")
    output$classification_preview <- renderTable(head(dataset))
  })
  
  # (G) Q&A logic
  initialize_conversation <- function(){
    list(list(role="researcher", content="Hello from user."))
  }
  conversation_history <- reactiveVal(initialize_conversation())
  
  observe({
    req(data_store())
    tryCatch({
      column_names <- names(data_store())
      updateSelectInput(session, "qa_columns", choices=column_names, selected=column_names)
    }, error=function(e){
      message("Error updating QA columns:", e$message)
      updateSelectInput(session, "qa_columns", choices=NULL)
    })
  })
  
  observeEvent(input$run_qa, {
    req(data_store(), input$qa_question, input$qa_columns)
    ds <- data_store()
    selected_cols <- input$qa_columns
    if (!all(selected_cols %in% names(ds))){
      showNotification("Select valid columns", type="warning")
      return()
    }
    n_rows <- nrow(ds)
    sample_size <- min(n_rows, as.integer(input$qa_sample_size))
    context_data <- ds %>% select(all_of(selected_cols)) %>%
      sample_n(sample_size)
    
    context_str <- paste(
      apply(context_data, 1, function(row) paste(names(row), row, sep=": ", collapse="; ")),
      collapse="\n"
    )
    
    conv <- conversation_history()
    conv <- append(conv, list(list(role="researcher", content=paste("Data:\n", context_str, "\n\n", input$qa_question))))
    
    withProgress(message="Processing Q&A", value=0, {
      tryCatch({
        conv <- qa_with_map_reduce(conv)
        conversation_history(conv)
        output$qa_status <- renderText("Message sent successfully!")
      }, error=function(e){
        output$qa_status <- renderText(paste("Error Q&A:", e$message))
      })
    })
  })
  
  observeEvent(input$reset_conversation, {
    conversation_history(initialize_conversation())
    output$qa_status <- renderText("Conversation reset.")
  })
  
  output$conversation_history <- renderText({
    conv <- conversation_history()
    paste(
      sapply(conv, function(msg) paste0(msg$role, ": ", msg$content)),
      collapse="\n\n"
    )
  })
  
  # (H) File viewer
  observeEvent(input$view_file, {
    df <- items_metadata()
    req(df)
    
    # Check for selection
    sel <- input$items_table_rows_selected
    if (length(sel) < 1) {
      showNotification("Select a row first", type = "warning")
      return()
    }
    
    # Ensure the 'path' column exists and is valid
    if (!"key" %in% names(df)) {
      showNotification("No file path information available in the selected item.", type = "error")
      return()
    }
    
    selected_row <- df[sel, ]
    file_path <- selected_row$key
    
    # Validate file path
    if (is.null(file_path) || file_path == "" || file_path == "(No Path)" || !file.exists(file_path)) {
      showNotification(paste("File not found or invalid path:", file_path), type = "error")
      return()
    }
    
    # Set file path for viewer
    selected_file(file_path)
  })
  

  output$file_viewer <- renderUI({
    req(selected_file())
    path <- normalizePath(selected_file(), mustWork = TRUE)
    ext <- tolower(file_ext(path))
    
    if (!dir.exists("www")) dir.create("www")
    temp_filename <- paste0("preview_file.", ext)
    dest_path <- file.path("www", temp_filename)
    file.copy(path, dest_path, overwrite = TRUE)
    
    if (ext == "pdf") {
      tags$iframe(style = "height:600px; width:100%;", src = temp_filename)
    } else if (ext == "docx") {
      content <- tryCatch(py$extract_text_from_docx(path), error = function(e) "Unable to read DOCX.")
      verbatimTextOutput("docx_preview")
    } else if (ext %in% c("pptx", "ppt")) {
      content <- tryCatch(py$extract_text_from_pptx(path), error = function(e) "Unable to read PowerPoint.")
      verbatimTextOutput("pptx_preview")
    } else if (ext %in% c("txt", "r", "py", "md", "json", "csv")) {
      content <- tryCatch(readLines(path, warn = FALSE), error = function(e) return("Unable to read file."))
      textAreaInput("file_contents", "Contents:", value = paste(content, collapse = "\n"), rows = 30, width = "100%")
    } else {
      p("Unsupported file type for preview.")
    }
  })
  
  output$docx_preview <- renderText({
    req(selected_file())
    py$extract_text_from_docx(normalizePath(selected_file(), mustWork = TRUE))
  })
  
  output$pptx_preview <- renderText({
    req(selected_file())
    py$extract_text_from_pptx(normalizePath(selected_file(), mustWork = TRUE))
  })
  
  
  
}

# Run app
shinyApp(ui = ui, server = server)