# Install the packages, automatically selecting the nearest CRAN mirror
#packages_to_install <- c("shiny", "reticulate", "DT", "dplyr", "stringr", "tools", "DBI", "RSQLite", "digest", "shinyjs", "purrr","commonmark","htmltools","jsonlite", "later")
#install.packages(packages_to_install, repos = "https://cloud.r-project.org")


library(shiny)
library(reticulate)
library(DT)
library(dplyr)
library(stringr)
library(tools)
library(DBI)
library(RSQLite)
library(digest)
library(shinyjs)
library(purrr)
library(commonmark)
library(htmltools)
library(jsonlite)
library(later)


# Python dependencies
required_python_packages <- c(
  "requests", "safetensors", "beautifulsoup4", "numpy", "inflect",
  "transformers", "torch", "pandas", "PyPDF2", "python-docx", "nltk", "python-pptx", "docx",
  "openai", "sentence_transformers", "accelerate>=0.26.0", "google.generativeai"
)

# Loop through the Python packages and install if not available
for (pkg in required_python_packages) {
  if (!reticulate::py_module_available(pkg)) {
    message("Installing Python package: ", pkg)
    reticulate::py_require(pkg)
  }
}


# Source Python files
source_python("Logeny/zotero_integration.py")
source_python("Logeny/vector_db_search.py")
source_python("Logeny/user_auth.py")
source_python("Logeny/classify_text.py")
source_python("Logeny/call_model_api.py")
source_python("Logeny/huggingface_model_runner.py")
source_python("Logeny/llm_memory_handler.py")
source_python("Logeny/openai_model_runner.py")
source_python("Logeny/llm_api_handler.py")
source_python("Logeny/llm_router.py")
source_python("Logeny/gemini_model_runner.py")




# UI
ui <- fluidPage(
  useShinyjs(),
  tags$style(HTML("
  .top-bar {
        display: flex;sb
        justify-content: flex-end;
        align-items: center;
        background-color: #ffffff;
        padding: 10px 20px 5px 10px;
        border-bottom: 1px solid #ddd;
      }
      .top-bar img {
        height: 40px;
        margin-right: 10px;
      }
      .top-bar .hub-title {
        font-size: 18px;
        font-weight: bold;
        color: #222;
        white-space: nowrap;
      }
      
  .chat-message {
    background: #f2f2f2;
    padding: 10px;
    margin-bottom: 10px;
    border-radius: 8px;
    max-width: 80%;
  }
  .chat-message strong {
    color: #333;
  }
  .chat-message small {
    color: #999;
    float: right;
  }    
  
  .chat-bubble {
    max-width: 70%;
    padding: 12px 15px;
    margin: 8px;
    border-radius: 12px;
    display: inline-block;
    word-wrap: break-word;
  }
  .user-message {
    background-color: #DCF8C6;
    float: right;
    clear: both;
  }
  .bot-message {
    background-color: #F1F0F0;
    float: left;
    clear: both;
  }
  .chat-window {
    border: 1px solid #ddd;
    padding: 10px;
    max-height: 500px;
    overflow-y: scroll;
    background-color: white;
  }
  
  .json-output {
    background-color: #f5f5f5;
      padding: 10px;
    border-radius: 5px;
    font-family: monospace;
    white-space: pre-wrap;
    word-wrap: break-word;
  }
                  

"))
  ,
  
  # Top bar with logo + text
  div(class = "top-bar",
      tags$img(src = "Logo JPG-06.jpg", alt = ""),
      span(class = "hub-title", "Logeny Semantic Knowledge Hub")
  ),
  tags$head(
    # CSS for chat bubbles
    tags$style(HTML("
    .chat-bubble {
      padding: 10px;
      border-radius: 10px;
      margin-bottom: 10px;
      max-width: 80%;
    }
    .user-message {
      background-color: #d1e7dd;
      align-self: flex-end;
    }
    .bot-message {
      background-color: #f8f9fa;
      align-self: flex-start;
    }
    code, pre {
      background-color: #f1f1f1;
      padding: 4px;
      border-radius: 4px;
      font-family: monospace;
      white-space: pre-wrap;
    }
  ")),
    
    # JavaScript for tag buttons
    tags$script(HTML("
      // Handle tag button clicks
      $(document).on('click', '.tag-btn', function() {
        var id = $(this).attr('id').split('_')[1];
        Shiny.setInputValue('tag_snippet_id', id, {priority: 'event'});
      });
    
      // Automatically scroll chat to bottom on new message
      Shiny.addCustomMessageHandler('scrollToBottom', function(dummy) {
        var chatWindow = document.querySelector('.chat-window');
        if (chatWindow) {
          chatWindow.scrollTop = chatWindow.scrollHeight;
        }
      });
    "))
    
  )
  
  ,
  
  uiOutput("main_ui"),
  
  # Add Ko-fi link and copyright
  hr(),
  div(style = "text-align: center;",
      br(),
      p("Copyright © 2024 Eola Organizational Research and Design LLC."),
      p("This beta version of Logeny is offered as a pay-what-you-can service."),
      a(href = "https://ko-fi.com/logeny#", "Support Logeny on Ko-fi", target = "_blank")
  )
)

# Server
server <- function(input, output, session) {
  db_path <- reactiveVal(NULL)
  current_user <- reactiveVal(NULL)
  project_note_data <- reactiveVal(NULL)
  data_store <- reactiveVal(NULL)
  items_metadata <- reactiveVal(NULL)
  selected_file <- reactiveVal(NULL)
  filtered_data <- reactiveVal(NULL)
  example_snippets <- reactiveVal(NULL)
  trigger_chat_history_update <- reactiveVal(0)
  chat_snippet_context <- reactiveVal(NULL)
  previewed_snippets <- reactiveVal(NULL)
  
  filter_choices <- reactiveValues(
    collections = NULL,
    categories = NULL,
    responses = NULL,
    sources = NULL
  )
  
  # Modal to tag a snippet
  tagModalUI <- function(snippet_id) {
    showModal(modalDialog(
      title = paste("Tag Snippet", snippet_id),
      textInput("tag_category", "Tag Category", value = ""),
      selectizeInput("tag_value", "Tag Value", choices = NULL, multiple = FALSE, options = list(create = TRUE)),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_tag", "Add Tag")
      )
    ))
  }
  
  get_existing_tags <- function(db_path) {
    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    tags <- DBI::dbGetQuery(con, "SELECT DISTINCT tagResponse FROM itemTags")
    DBI::dbDisconnect(con)
    return(tags$tagResponse)
  }
  
  
  observeEvent(input$tag_snippet_id, {
    snippet_id <- as.integer(input$tag_snippet_id)
    
    # Get current tag categories for autocomplete
    tag_cats <- tryCatch({
      conn <- dbConnect(RSQLite::SQLite(), db_path())
      existing <- dbGetQuery(conn, "SELECT DISTINCT tagCategory FROM snippet_tags")
      dbDisconnect(conn)
      existing$tagCategory
    }, error = function(e) character(0))
    
    showModal(modalDialog(
      title = paste("Tag Snippet", snippet_id),
      textInput("tag_category", "Tag Category", value = ""),
      selectizeInput("tag_value", "Tag Value", choices = NULL, options = list(create = TRUE)),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_tag_btn", "Add Tag")
      )
    ))
    
    updateSelectizeInput(session, "tag_category", choices = tag_cats, server = TRUE)
    updateTextInput(session, "tag_value", value = "")  # reset
  })
  
  observeEvent(input$confirm_tag_btn, {
    req(current_user(), input$tag_category, input$tag_value, input$tag_snippet_id)
    
    tryCatch({
      conn <- dbConnect(RSQLite::SQLite(), db_path())
      dbExecute(conn, "
      INSERT INTO snippet_tags (snippetID, tagCategory, tagResponse, tagSource)
      VALUES (?, ?, ?, ?)",
                params = list(
                  as.integer(input$tag_snippet_id),
                  input$tag_category,
                  input$tag_value,
                  current_user()$username
                )
      )
      dbDisconnect(conn)
      showNotification("Tag saved!", type = "message")
    }, error = function(e) {
      showNotification(paste("Error saving tag:", e$message), type = "error")
    })
    
    removeModal()
  })
  
  
  # Dynamic UI
  output$main_ui <- renderUI({
    if (is.null(current_user())) {
      fluidRow(
        column(6, offset = 1,
               wellPanel(
                 h4("Enter Project Folder:"),
                 textInput("db_folder", NULL, value = "document library"),
                 actionButton("db_connect", "Connect or Create DB"),
                 br(), br(),
                 uiOutput("auth_ui"),
                 textOutput("auth_status")
               ))
      )
    } else {
      tagList(
        #h4(paste("Logged in as:", current_user()$username, "| Role:", current_user()$role)),
        tabsetPanel(
          tabPanel("Sync Folder",
                   br(),
                   actionButton("refresh_db", "Referesh DB"),
                   numericInput("chunk_size", "Chunk Size (# words)", value = 150, min = 5),
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
                       numericInput("vsearch_topk", "Number of Results", value = 20, min = 1),
                       actionButton("run_vsearch", "Run Semantic Search"),
                       actionButton("load_prior_search", "Prior Search Results")
                     ),
                     mainPanel(DTOutput("saved_snippets_table"))
                   )
          ),
          tabPanel("Text Classification",
                   fluidPage(
                     #titlePanel("Text Classification"),
                     sidebarLayout(
                       sidebarPanel(
                         #h4("Classifier Setup"),
                         selectInput("text_column", "Select Column to Classify", choices = c(), selected = NULL),
                         textInput("classifier_tag", "Classifier Tag", value = "sentiment"),
                         textAreaInput("classification_prompt", 
                                       "Classification Prompt", 
                                       "Please classify the following text based on the terms provided."),
                         textInput("classification_terms", 
                                   "Classification Terms (comma-separated)", 
                                   value = "positive, negative, neutral"),
                         actionButton("run_classification", "Run Classification"),
                         
                         br(), br(),
                         tags$hr(),
                         checkboxInput("show_pre_filters", "Show Pre-classification Filters", value = FALSE),
                         conditionalPanel(
                           condition = "input.show_pre_filters == true",
                           h5("Pre-classification Filters"),
                           selectInput("filter_query", "Query Term", choices = c(), selected = NULL),
                           selectInput("filter_collection_name", "Collection Name", choices = c("All Documents")),
                           dateRangeInput("filter_timestamp", "Date Range", start = Sys.Date() - 30, end = Sys.Date()),
                           actionButton("filter_data", "Apply Filters"),
                           actionButton("reset_pre_filters", "Reset Pre-filters", icon = icon("redo"))
                           
                         ),
                         
                         tags$hr(),
                         checkboxInput("show_example_filters", "Show Example Tag Filters", value = FALSE),
                         conditionalPanel(
                           condition = "input.show_example_filters == true",
                           h5("Example Snippet Filters (for in-context examples)"),
                           selectInput("example_tagCategory", "Tag Category", choices = c()),
                           selectInput("example_tagResponse", "Tag Response", choices = c()),
                           selectInput("example_tagSource", "Tag Source", choices = c()),
                           numericInput("example_K", "Number of Examples", value = 3, min = 1, max = 10),
                           actionButton("preview_examples", "Preview Example Snippets"),
                           actionButton("reset_example_filters", "Reset Example Filters", icon = icon("redo"))
                           
                         ),
                         
                         textOutput("classification_status")
                       ),
                       mainPanel(
                         tableOutput("classification_preview")
                       )
                     )
                   ))
          ,
          tabPanel("Chat with Model",
                   fluidPage(
                     #titlePanel("Chat with GPT"),
                     sidebarLayout(
                       sidebarPanel(
                         h4("Setup"),
                         selectInput("selected_model", "Choose a Model", choices = c(), selected = NULL),
                         selectInput("chat_thread", "Select Thread", choices = NULL, selected = NULL),
                         textInput("new_thread", "New Thread Name (optional)", value = ""),
                         actionButton("start_thread", "Start New Thread"),
                         tags$hr(),
                         #h4("Grounding Interface:"),
                         numericInput("k_last_messages", "Number of Past Messages to Include:", value = 5, min = 1),
                         checkboxInput("use_full_history", "Use Full History Instead", value = FALSE),
                         
                         tags$hr(),
                         checkboxInput("show_chat_filters", "Use Tagged Snippetts", value = FALSE),
                         conditionalPanel(
                           condition = "input.show_chat_filters == true",
                           selectInput("chat_filter_query", "Query Term", choices = c(), selected = NULL),
                           selectInput("chat_filter_collection", "Collection", choices = c()),
                           selectInput("chat_filter_tagCategory", "Tag Category", choices = c(), selected = NULL),
                           selectInput("chat_filter_tagResponse", "Tag Response", choices = c(), selected = NULL),
                           selectInput("chat_filter_tagSource", "Tag Source", choices = c(), selected = NULL),
                           numericInput("chat_example_K", "Number of Snippets", value = 3, min = 1, max = 10),
                           actionButton("chat_preview_context", "Preview Context"),
                           actionButton("refresh_chat_context", "Refresh Context Snippets", icon = icon("redo"))  
                           
                         ),
                         
                         tags$hr(),
                         checkboxInput("show_doc_options", "Include Collection Documents", value = FALSE),
                         conditionalPanel(
                           condition = "input.show_doc_options == true",
                           selectizeInput(
                             "chat_doc_select", 
                             "Select Context Documents", 
                             choices = c(), 
                             selected = NULL, 
                             multiple = TRUE
                           ),
                           selectInput("working_doc_select", "Select Working Document", choices = c()),
                           checkboxInput("use_as_working_doc", "Enable Editing Working Doc", value = FALSE),
                           actionButton("refresh_doc_choices", "Refresh Document Selections", icon = icon("redo"))
                         )
                         
                       ),
                       
                       mainPanel(
                         br(),
                         div(class = "chat-window", uiOutput("chat_bubbles")),                                                 #uiOutput("chat_history"),
                         br(),
                         textAreaInput("chat_input", NULL, placeholder = "Start typing...", rows = 3, width = "100%"),
                         actionButton("send_chat", label = NULL, icon = icon("paper-plane"), class = "btn btn-primary"),
                         tags$hr()
                         
                       )
                       
                     )
                   )
          )
          
          
          ,
          tabPanel("File Viewer", uiOutput("file_viewer")),
          tabPanel("Teams",
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
    
    con <- dbConnect(RSQLite::SQLite(), db_path())
    filter_choices$collections <- dbGetQuery(con, "SELECT DISTINCT collection_name FROM search_results")$collection_name
    filter_choices$categories <- dbGetQuery(con, "SELECT DISTINCT tagCategory FROM snippet_tags")$tagCategory
    filter_choices$responses  <- dbGetQuery(con, "SELECT DISTINCT tagResponse FROM snippet_tags")$tagResponse
    filter_choices$sources    <- dbGetQuery(con, "SELECT DISTINCT tagSource FROM snippet_tags")$tagSource
    dbDisconnect(con)
    
    # Add user to entities table if not already present
    con <- DBI::dbConnect(RSQLite::SQLite(), db_path())
    user_entity_check <- DBI::dbGetQuery(con, "
  SELECT entity_id FROM entities
  WHERE entity_name = ? AND entity_type = 'user'
", params = list(input$login_username))
    
    if (nrow(user_entity_check) == 0) {
      DBI::dbExecute(con, "
    INSERT INTO entities (entity_name, entity_type)
    VALUES (?, 'user')
  ", params = list(input$login_username))
      message("Inserted new user entity: ", input$login_username)
    }
    DBI::dbDisconnect(con)
    
    
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
  #observe({
  #  req(db_path())
  #  tryCatch({
  #    coll_names <- py$get_all_collections(db_path())
  #    coll_names <- c("All Documents", coll_names)
  #    updateSelectInput(session, "collection_name", choices=coll_names, selected="All Documents")
  #  }, error=function(e){
  #    message("Error loading collections: ", e$message)
  #  })
  #})
  
  #Auto Loads
  # Update thread dropdown on login
  observeEvent(current_user(), {
    req(db_path())
    con <- dbConnect(RSQLite::SQLite(), db_path())
    threads <- dbGetQuery(con, "
    SELECT DISTINCT tagResponse AS thread
    FROM itemTags
    WHERE tagCategory = 'chat_thread'
  ")$thread
    dbDisconnect(con)
    
    updateSelectInput(session, "chat_thread", choices = threads, selected = NULL)
  })
  
  # Start new thread
  observeEvent(input$start_thread, {
    req(input$new_thread, current_user(), db_path())
    
    con <- dbConnect(RSQLite::SQLite(), db_path())
    
    tryCatch({
      # Step 1: Insert a new item with key only
      dbExecute(con, "
        INSERT INTO items (key, itemTypeID)
        VALUES (?, ?)
      ", params = list(
        paste0("thread_root_", input$new_thread),
        -1  # Use -1 or 0 to indicate a placeholder
      ))
      
      
      itemID <- dbGetQuery(con, "SELECT last_insert_rowid()")[[1]]
      
      # Step 2: Generate timestamp manually in R
      ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      
      # Step 3: Add all relevant tags
      dbExecute(con, "
      INSERT INTO itemTags (itemID, tagCategory, tagResponse, tagSource)
      VALUES 
        (?, 'item_type', 'chat', ?),
        (?, 'chat_thread', ?, ?),
        (?, 'sender', ?, ?),
        (?, 'note_content', ?, ?),
        (?, 'created_at', ?, ?)
    ", params = c(
      itemID, current_user()$username,
      itemID, input$new_thread, current_user()$username,
      itemID, current_user()$username, current_user()$username,
      itemID, paste("Started thread:", input$new_thread), current_user()$username,
      itemID, ts, current_user()$username
    ))
      
      # Step 4: Update UI
      threads <- dbGetQuery(con, "
      SELECT DISTINCT tagResponse AS thread
      FROM itemTags
      WHERE tagCategory = 'chat_thread'
    ")$thread
      
      updateSelectInput(session, "chat_thread", choices = threads, selected = input$new_thread)
      updateTextInput(session, "new_thread", value = "")
      
      showNotification("New thread started and selected.", type = "message")
      trigger_chat_history_update(runif(1))
      
    }, error = function(e) {
      showNotification(paste("Error starting thread:", e$message), type = "error")
    }, finally = {
      dbDisconnect(con)
    })
  })
  

  
  # Teams Tab
  observe({
    req(db_path(), current_user())
    project <- input$msg_project_filter
    
    tryCatch({
      con <- dbConnect(RSQLite::SQLite(), db_path())
      
      query <- "
      SELECT i.content AS note_content, 
             IFNULL(sender_tags.tagResponse, 'system') AS created_by, 
             i.created_at
      FROM items i
      JOIN itemTags proj_tags ON i.itemID = proj_tags.itemID
      LEFT JOIN itemTags sender_tags ON i.itemID = sender_tags.itemID AND sender_tags.tagCategory = 'sender'
      JOIN entities e ON e.entity_name = ? AND e.entity_type = 'project'
      WHERE proj_tags.tagCategory = 'project' AND proj_tags.tagResponse = e.entity_name
      ORDER BY i.created_at DESC
    "
      
      df <- dbGetQuery(con, query, params = list(project))
      dbDisconnect(con)
      
      output$message_table <- renderDT({
        datatable(df, options = list(pageLength = 5), rownames = FALSE)
      })
      
    }, error = function(e) {
      output$message_table <- renderDT({
        datatable(data.frame(Note = "Unable to load messages"))
      })
    })
    
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
  
  #Add project notes
  observeEvent(input$add_note, {
    req(current_user(), input$new_note, db_path(), input$msg_project_filter)
    
    project <- input$msg_project_filter
    note_content <- input$new_note
    
    tryCatch({
      con <- dbConnect(RSQLite::SQLite(), db_path())
      
      # Insert new item
      dbExecute(con, "INSERT INTO items (key, itemTypeID) VALUES (?, ?)",
                params = list(paste0("project_note_", Sys.time()), -1)) #Placeholder itemTypeID
      
      item_id <- dbGetQuery(con, "SELECT last_insert_rowid()")$`last_insert_rowid()`
      
      # Add tags
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      dbExecute(con, "INSERT INTO itemTags (itemID, tagCategory, tagResponse, tagSource) VALUES
              (?, 'item_type', 'project_note', ?),
              (?, 'project', ?, ?),
              (?, 'sender', ?, ?),
              (?, 'note_content', ?, ?),
              (?, 'created_at', ?, ?)",
                params = list(
                  item_id, current_user()$username,
                  item_id, project, current_user()$username,
                  item_id, current_user()$username, current_user()$username,
                  item_id, note_content, current_user()$username,
                  item_id, timestamp, current_user()$username
                ))
      
      dbDisconnect(con)
      
      updateTextInput(session, "new_note", value = "")
      showNotification("Note added successfully!", type = "message")
      
    }, error = function(e) {
      showNotification(paste("Error adding note:", e$message), type = "error")
    })
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
  
  
  # (D) Vector Search 1
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
  
  # (D) Vector Search 2
  observeEvent(input$load_prior_search, {
    req(db_path(), input$collection_name)
    # call vector_db_search
    tryCatch({
      # Retrieve enriched results from the DB (with document name)
      df <- get_search_results(db_path(), collection_name = input$collection_name)
      if (nrow(df) == 0){
        showNotification("No vector-based matches found.", type = "warning")
        data_store(data.frame(Note = "No existing search results."))
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
    req(df)
    
    # Add a new column with action buttons
    df$Actions <- mapply(function(snippet_id) {
      sprintf('
    <div class="btn-group" role="group">
      <button class="btn btn-success btn-sm" onclick="Shiny.setInputValue(\'good_match\', %s, {priority: \'event\'})">Match Good</button>
      <button class="btn btn-secondary btn-sm" onclick="Shiny.setInputValue(\'bad_match\', %s, {priority: \'event\'})">Match Bad</button>
      <button class="btn btn-dark btn-sm tag-btn" id="tag_%s">Tag</button>
    </div>', snippet_id, snippet_id, snippet_id)
    }, df$snippetID, USE.NAMES = FALSE)
    
    
    datatable(df,
              escape = FALSE,
              selection = "none",
              rownames = FALSE,
              options = list(pageLength = 10, autoWidth = TRUE),
              colnames = c("Snippet ID", "Query", "Matched Word", "Context", "Collection", "Time", "Document", "Actions")
    )
  })
  
  # Tag snippets
  observeEvent(input$saved_snippets_table_rows_selected, {
    sel_row <- input$saved_snippets_table_rows_selected
    df <- data_store()
    req(sel_row, df)
    sel_snippet <- df[sel_row, ]
    snippet_id <- sel_snippet$snippetID
    
    tag_cats <- tryCatch({
      conn <- dbConnect(RSQLite::SQLite(), db_path())
      existing <- dbGetQuery(conn, "SELECT DISTINCT tagCategory FROM snippet_tags")
      dbDisconnect(conn)
      existing$tagCategory
    }, error = function(e) character(0))
    
    showModal(modalDialog(
      title = paste("Tag Snippet", snippet_id),
      textInput("tag_category", "Tag Category", value = ""),
      selectizeInput("tag_value", "Tag Value", choices = NULL, options = list(create = TRUE)),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_tag", "Add Tag")
      )
    ))
    
    # Set dynamic default for autocomplete input
    updateSelectizeInput(session, "tag_category", choices = tag_cats, server = TRUE)
  })
  observeEvent(input$confirm_tag, {
    req(current_user(), input$tag_category, input$tag_value)
    sel_row <- isolate(input$saved_snippets_table_rows_selected)
    df <- data_store()
    req(sel_row, df)
    snippet_id <- df[sel_row, "snippetID"]
    
    tryCatch({
      conn <- dbConnect(RSQLite::SQLite(), db_path())
      dbExecute(conn, "
      INSERT INTO snippet_tags (snippetID, tagCategory, tagResponse, tagSource)
      VALUES (?, ?, ?, ?)",
                params = list(snippet_id, input$tag_category, input$tag_value, current_user()$username)
      )
      dbDisconnect(conn)
      showNotification("Tag added!", type = "message")
    }, error = function(e) {
      showNotification(paste("Error adding tag:", e$message), type = "error")
    })
    
    removeModal()
  })
  
  # Tag match agreement
  observeEvent(input$good_match, {
    tryCatch({
      conn <- dbConnect(RSQLite::SQLite(), db_path())
      dbExecute(conn, "
      INSERT INTO snippet_tags (snippetID, tagCategory, tagResponse, tagSource)
      VALUES (?, 'match_agreement', 'good', ?)",
                params = list(input$good_match, current_user()$username)
      )
      dbDisconnect(conn)
      showNotification("Tagged as GOOD match.", type = "message")
    }, error = function(e) {
      showNotification(paste("Error tagging:", e$message), type = "error")
    })
  })
  
  observeEvent(input$bad_match, {
    tryCatch({
      conn <- dbConnect(RSQLite::SQLite(), db_path())
      dbExecute(conn, "
      INSERT INTO snippet_tags (snippetID, tagCategory, tagResponse, tagSource)
      VALUES (?, 'match_agreement', 'bad', ?)",
                params = list(input$bad_match, current_user()$username)
      )
      dbDisconnect(conn)
      showNotification("Tagged as BAD match.", type = "message")
    }, error = function(e) {
      showNotification(paste("Error tagging:", e$message), type = "error")
    })
  })
  
  
  
  # (F) Classification Server logic
  observe({
    req(data_store())
    tryCatch({
      column_names <- names(data_store())
      observe({
        req(data_store())
        tryCatch({
          column_names <- names(data_store())
          text_columns <- column_names[sapply(data_store(), is.character)]
          updateSelectInput(session, "text_column", choices = text_columns, selected = text_columns[1])
        }, error=function(e){
          message("Error updating classification columns:", e$message)
        })
      })
      
      updateSelectInput(session, "text_column", choices=column_names, selected=column_names[1])
    }, error=function(e){
      message("Error updating classification columns:", e$message)
    })
  })
  
  observeEvent(input$filter_data, {
    req(db_path())
    con <- dbConnect(RSQLite::SQLite(), db_path())
    on.exit(dbDisconnect(con))
    
    base_query <- "SELECT snippetID, query, matched_word, context, collection_name, timestamp FROM search_results WHERE 1=1"
    params <- list()
    
    if (nzchar(input$filter_query)) {
      base_query <- paste(base_query, "AND query LIKE ?")
      params <- append(params, paste0("%", input$filter_query, "%"))
    }
    if (input$filter_collection_name != "" && input$filter_collection_name != "All Documents") {
      base_query <- paste(base_query, "AND collection_name = ?")
      params <- append(params, input$filter_collection_name)
    }
    if (!is.null(input$filter_timestamp) && length(input$filter_timestamp) == 2) {
      base_query <- paste(base_query, "AND date(timestamp) BETWEEN ? AND ?")
      params <- append(params, as.character(input$filter_timestamp[1]))
      params <- append(params, as.character(input$filter_timestamp[2]))
    }
    
    df <- dbGetQuery(con, base_query, params = params)
    filtered_data(df)
    showNotification("Filtered data loaded for classification.", type = "message")
  })
  
  
  observeEvent(input$preview_examples, {
    req(db_path())
    
    con <- dbConnect(RSQLite::SQLite(), db_path())
    conditions <- c()
    params <- list()
    
    if (!is.null(input$example_tagCategory) && nzchar(input$example_tagCategory)) {
      conditions <- c(conditions, "tagCategory = ?")
      params <- append(params, input$example_tagCategory)
    }
    if (!is.null(input$example_tagResponse) && nzchar(input$example_tagResponse)) {
      conditions <- c(conditions, "tagResponse = ?")
      params <- append(params, input$example_tagResponse)
    }
    if (!is.null(input$example_tagSource) && nzchar(input$example_tagSource)) {
      conditions <- c(conditions, "tagSource = ?")
      params <- append(params, input$example_tagSource)
    }
    
    if (length(conditions) == 0) {
      showNotification("Please select at least one tag filter.", type = "warning")
      dbDisconnect(con)
      return()
    }
    
    where_clause <- paste(conditions, collapse = " AND ")
    query <- sprintf("
    SELECT sr.context, st.tagResponse
    FROM snippet_tags st
    JOIN search_results sr ON sr.snippetID = st.snippetID
    WHERE %s
    ORDER BY RANDOM()
    LIMIT ?
  ", where_clause)
    
    params <- append(params, input$example_K)
    
    examples <- dbGetQuery(con, query, params = params)
    dbDisconnect(con)
    
    if (nrow(examples) == 0) {
      showModal(modalDialog(
        title = "No Matching Examples",
        "No snippets matched your filters. Try relaxing them.",
        easyClose = TRUE
      ))
    } else {
      example_snippets(examples)
      showModal(modalDialog(
        title = "Sampled Example Snippets",
        renderTable({ examples }),
        easyClose = TRUE
      ))
    }
  })
  
  
  
  
  observeEvent(current_user(), {
    req(db_path())
    
    tryCatch({
      con <- dbConnect(RSQLite::SQLite(), db_path())
      
      # Pre-classification: query values
      query_vals <- dbGetQuery(con, "SELECT DISTINCT query FROM search_results")$query
      updateSelectInput(session, "filter_query", choices = query_vals)
      
      coll_vals <- dbGetQuery(con, "SELECT DISTINCT collection_name FROM search_results")$collection_name
      updateSelectInput(session, "filter_collection_name", choices = c("All Documents", coll_vals))
      
      # Example (tag-based) filters
      tag_cats <- c("", dbGetQuery(con, "SELECT DISTINCT tagCategory FROM snippet_tags")$tagCategory)
      tag_responses <- c("", dbGetQuery(con, "SELECT DISTINCT tagResponse FROM snippet_tags")$tagResponse)
      tag_sources <- c("", dbGetQuery(con, "SELECT DISTINCT tagSource FROM snippet_tags")$tagSource)
      
      updateSelectizeInput(session, "example_tagCategory", choices = c("", tag_cats), selected = "")
      updateSelectizeInput(session, "example_tagResponse", choices = c("", tag_responses), selected = "")
      updateSelectizeInput(session, "example_tagSource", choices = c("", tag_sources), selected = "")
      
      dbDisconnect(con)
    }, error = function(e) {
      message("Error updating filter options: ", e$message)
    })
  })
  
  
  observeEvent(input$run_classification, {
    req(
      data_store(),
      input$text_column,
      input$classifier_tag,
      input$classification_prompt,
      input$classification_terms,
      current_user()
    )
    
    dataset <- if (!is.null(filtered_data())) filtered_data() else data_store()
    
    txt_col <- dataset[[input$text_column]]
    prompt  <- input$classification_prompt
    terms   <- str_split(input$classification_terms, ",\\s*")[[1]]
    model_tag <- "valhalla/distilbart-mnli-12-1"  # or make dynamic later
    
    # -----------------------------
    # (1) Sample example snippets from DB if tag filters are used
    # -----------------------------
    example_text <- NULL
    if (input$show_example_filters) {
      con <- dbConnect(RSQLite::SQLite(), db_path())
      conditions <- c()
      params <- list()
      
      if (!is.null(input$example_tagCategory) && input$example_tagCategory != "") {
        conditions <- c(conditions, "tagCategory = ?")
        params <- append(params, input$example_tagCategory)
      }
      if (!is.null(input$example_tagResponse) && input$example_tagResponse != "") {
        conditions <- c(conditions, "tagResponse = ?")
        params <- append(params, input$example_tagResponse)
      }
      if (!is.null(input$example_tagSource) && input$example_tagSource != "") {
        conditions <- c(conditions, "tagSource = ?")
        params <- append(params, input$example_tagSource)
      }
      
      if (length(conditions) > 0) {
        tag_filter_clause <- paste(conditions, collapse = " AND ")
        
        query <- sprintf("
        SELECT sr.context, st.tagResponse
        FROM snippet_tags st
        JOIN search_results sr ON sr.snippetID = st.snippetID
        WHERE %s
        ORDER BY RANDOM()
        LIMIT ?
      ", tag_filter_clause)
        
        params <- append(params, input$example_K)
        example_rows <- dbGetQuery(con, query, params = params)
        
        if (nrow(example_rows) > 0) {
          formatted <- apply(example_rows, 1, function(row) {
            paste0("Text: ", row[["context"]], "\nLabel: ", row[["tagResponse"]])
          })
          example_text <- paste(formatted, collapse = "\n\n")
        }
      }
      
      dbDisconnect(con)
    }
    
    # -----------------------------
    # (2) Run classification
    # -----------------------------
    withProgress(message = "Running classification", value = 0, {
      results <- map_chr(txt_col, ~ {
        context_txt <- .x
        full_prompt <- if (!is.null(example_text)) {
          paste(prompt, "\n\nExamples:\n", example_text, "\n\nNow classify this:\n", context_txt)
        } else {
          paste(prompt, "\n\nText:\n", context_txt)
        }
        message("---- Prompt Sent to Classifier ----\n", full_prompt, "\n-------------------------------\n")
        
        classify_text_with_map_reduce(list(context_txt), full_prompt, terms)
      }, .progress = TRUE)
    })
    
    # -----------------------------
    # (3) Save to DB as tags
    # -----------------------------
    tryCatch({
      con <- dbConnect(RSQLite::SQLite(), db_path())
      for (i in seq_along(results)) {
        dbExecute(con, "
        INSERT INTO snippet_tags (snippetID, tagCategory, tagResponse, tagSource)
        VALUES (?, ?, ?, ?)",
                  params = list(
                    dataset$snippetID[i],
                    input$classifier_tag,
                    results[i],
                    paste0(current_user()$username, "+", model_tag)
                  )
        )
      }
      dbDisconnect(con)
    }, error = function(e) {
      showNotification(paste("Error saving classifications:", e$message), type = "error")
    })
    
    
    # -----------------------------
    # (4) UI feedback
    # -----------------------------
    preview_df <- dataset %>%
      select(snippetID, query, matched_word, context, collection_name, timestamp) %>%
      mutate(!!input$classifier_tag := results)
    
    output$classification_preview <- renderTable(preview_df)
    output$classification_status <- renderText("Classification complete and saved.")
  })
  
  observeEvent(input$reset_example_filters, {
    req(
      db_path()
    )
    
    updateSelectizeInput(session, "example_tagCategory", choices = NULL, selected = NULL)
    updateSelectizeInput(session, "example_tagResponse", choices = NULL, selected = NULL)
    updateSelectizeInput(session, "example_tagSource", choices = NULL, selected = NULL)
    updateNumericInput(session, "example_K", value = 3)
    
    # Refresh available choices from DB to restore them after reset
    if (!is.null(db_path())) {
      tryCatch({
        con <- DBI::dbConnect(RSQLite::SQLite(), db_path())
        
        tag_cats <- dbGetQuery(con, "SELECT DISTINCT tagCategory FROM snippet_tags")$tagCategory
        tag_responses <- dbGetQuery(con, "SELECT DISTINCT tagResponse FROM snippet_tags")$tagResponse
        tag_sources <- dbGetQuery(con, "SELECT DISTINCT tagSource FROM snippet_tags")$tagSource
        
        updateSelectizeInput(session, "example_tagCategory", choices = c("", tag_cats), selected = "")
        updateSelectizeInput(session, "example_tagResponse", choices = c("", tag_responses), selected = "")
        updateSelectizeInput(session, "example_tagSource", choices = c("", tag_sources), selected = "")
        
        dbDisconnect(con)
      }, error = function(e) {
        showNotification(paste("Failed to reset filters:", e$message), type = "error")
      })
    }
  })
  
  
  observeEvent(input$reset_pre_filters, {
    updateSelectInput(session, "filter_query", selected = "")
    updateSelectInput(session, "filter_collection_name", selected = "All Documents")
    updateDateRangeInput(session, "filter_timestamp", 
                         start = Sys.Date() - 30, end = Sys.Date())
  })
  
  
  
  # (G) Q&A logic
  observe({
    req(db_path(), current_user())
    
    tryCatch({
      con <- dbConnect(RSQLite::SQLite(), db_path())
      models_df <- dbGetQuery(con, "
      SELECT entity_name AS model_name
      FROM entities
      WHERE entity_type = 'model'
      ORDER BY model_name
    ")
      dbDisconnect(con)
      
      model_choices <- models_df$model_name
      if (length(model_choices) > 0) {
        default_model <- if ("gemini-1.5-flash" %in% model_choices) "gemini-1.5-flash" else model_choices[1]
        updateSelectInput(session, "selected_model", choices = model_choices, selected = default_model)
        
      } else {
        updateSelectInput(session, "selected_model", choices = c("No models available"), selected = NULL)
      }
    }, error = function(e) {
      message("Failed to load model choices: ", e$message)
    })
  })
  
  output$chat_bubbles <- renderUI({
    req(db_path(), input$chat_thread, trigger_chat_history_update())
    
    con <- dbConnect(RSQLite::SQLite(), db_path())
    
    # Pull chat messages + sender tag
    query <- "
  SELECT
    it1.tagResponse AS note_content,
    it2.tagResponse AS sender,
    it3.tagResponse AS created_at
  FROM items i
  JOIN itemTags it1 ON i.itemID = it1.itemID AND it1.tagCategory = 'note_content'
  JOIN itemTags it2 ON i.itemID = it2.itemID AND it2.tagCategory = 'sender'
  JOIN itemTags it3 ON i.itemID = it3.itemID AND it3.tagCategory = 'created_at'
  JOIN itemTags thread ON i.itemID = thread.itemID
  WHERE thread.tagCategory = 'chat_thread' AND thread.tagResponse = ?
  ORDER BY created_at
  "
    chat_df <- dbGetQuery(con, query, params = list(input$chat_thread))
    dbDisconnect(con)
    
    if (nrow(chat_df) == 0) {
      return(HTML("<em>No messages yet.</em>"))
    }
    
    # Construct chat bubbles
    chat_bubbles <- apply(chat_df, 1, function(row) {
      sender <- ifelse(is.na(row[["sender"]]), "Unknown", row[["sender"]])
      raw_text <- row[["note_content"]]
      timestamp <- row[["created_at"]]
      
      is_json <- grepl("^```json", raw_text) && grepl("```$", raw_text)
      
      if (is_json) {
        json_string <- sub("^```json\\s*", "", raw_text)
        json_string <- sub("\\s*```$", "", json_string)
        parsed <- tryCatch(jsonlite::fromJSON(json_string), error = function(e) NULL)
        if (!is.null(parsed)) {
          pretty_json <- jsonlite::prettify(jsonlite::toJSON(parsed, pretty = TRUE, auto_unbox = TRUE))
          html_content <- tags$pre(class = "json-output", HTML(paste0("<code>", pretty_json, "</code>")))
        } else {
          html_content <- tags$pre(class = "json-output", HTML(json_string))
        }
      } else {
        markdown_html <- commonmark::markdown_html(raw_text)
        html_content <- HTML(markdown_html)
      }
      
      class <- if (sender == current_user()$username) "user-message" else "bot-message"
      
      paste0(
        "<div class='chat-bubble ", class, "'>",
        "<strong>", sender, ":</strong><br>",
        html_content,
        "<br><small>", timestamp, "</small></div>"
      )
    })
    
    # Now trigger scroll once inner content is rendered
    session$sendCustomMessage("scrollToBottom", NULL)
    
    HTML(paste(chat_bubbles, collapse = ""))
  })
  
  
  observeEvent(input$refresh_doc_choices, {
    req(db_path())
    tryCatch({
      con <- dbConnect(RSQLite::SQLite(), db_path())
      on.exit(dbDisconnect(con), add = TRUE)
      
      items_df <- dbGetQuery(con, "SELECT itemID, key FROM items")
      
      if (nrow(items_df) > 0) {
        items_df$title <- tools::file_path_sans_ext(basename(items_df$key))
        names_vec <- setNames(items_df$itemID, items_df$title)
        
        updateSelectInput(session, "chat_doc_select", choices = names_vec, selected = NULL)
        updateSelectInput(session, "working_doc_select", choices = names_vec, selected = NULL)
      } else {
        showNotification("No documents found in database.", type = "warning")
      }
    }, error = function(e) {
      showNotification(paste("Error loading document selections:", e$message), type = "error")
      message("Error in refresh_doc_choices observeEvent:", e$message)
    })
  })
  
  
  observeEvent(input$refresh_chat_context, {
    req(db_path())
    
    tryCatch({
      con <- dbConnect(RSQLite::SQLite(), db_path())
      
      tag_cats <- dbGetQuery(con, "SELECT DISTINCT tagCategory FROM snippet_tags")$tagCategory
      tag_responses <- dbGetQuery(con, "SELECT DISTINCT tagResponse FROM snippet_tags")$tagResponse
      tag_sources <- dbGetQuery(con, "SELECT DISTINCT tagSource FROM snippet_tags")$tagSource
      queries <- dbGetQuery(con, "SELECT DISTINCT query FROM search_results")$query
      colls <- dbGetQuery(con, "SELECT DISTINCT collection_name FROM search_results")$collection_name
      
      updateSelectInput(session, "chat_filter_query", choices = c("", queries), selected = "")
      updateSelectInput(session, "chat_filter_collection", choices = c("", "All Documents", colls), selected = "")
      updateSelectInput(session, "chat_filter_tagCategory", choices = c("", tag_cats), selected = "")
      updateSelectInput(session, "chat_filter_tagResponse", choices = c("", tag_responses), selected = "")
      updateSelectInput(session, "chat_filter_tagSource", choices = c("", tag_sources), selected = "")
      
      dbDisconnect(con)
      showNotification("Chat snippet context options refreshed.", type = "message")
      
    }, error = function(e) {
      showNotification(paste("Error refreshing filters:", e$message), type = "error")
    })
  })
  
  
  
  observeEvent(input$chat_preview_context, {
    req(db_path())
    
    con <- dbConnect(RSQLite::SQLite(), db_path())
    
    # Start query and filter components
    base_query <- "
    SELECT sr.snippetID, sr.context
    FROM search_results sr
    JOIN snippet_tags st ON sr.snippetID = st.snippetID
    WHERE 1 = 1
  "
    filters <- c()
    params <- list()
    
    # Add filters only if user selected them
    if (!is.null(input$chat_filter_tagCategory) && nzchar(input$chat_filter_tagCategory)) {
      filters <- c(filters, "AND st.tagCategory = ?")
      params <- append(params, input$chat_filter_tagCategory)
    }
    
    if (!is.null(input$chat_filter_tagResponse) && nzchar(input$chat_filter_tagResponse)) {
      filters <- c(filters, "AND st.tagResponse = ?")
      params <- append(params, input$chat_filter_tagResponse)
    }
    
    if (!is.null(input$chat_filter_tagSource) && nzchar(input$chat_filter_tagSource)) {
      filters <- c(filters, "AND st.tagSource = ?")
      params <- append(params, input$chat_filter_tagSource)
    }
    
    filters <- paste(filters, collapse = " ")
    final_query <- paste(base_query, filters, "ORDER BY sr.timestamp DESC LIMIT ?")
    params <- append(params, input$chat_example_K)
    
    snippet_df <- dbGetQuery(con, final_query, params = params)
    dbDisconnect(con)
    
    #print(snippet_df)
    
    if (nrow(snippet_df) > 0) {
      previewed_snippets(snippet_df)
      
      output$snippet_preview_table <- renderTable({ previewed_snippets() })
      
      showModal(modalDialog(
        title = "Chat Snippet Context",
        tableOutput("snippet_preview_table"),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("push_snippets_to_prompt", "Push to Prompt")
        ),
        easyClose = TRUE
      ))
    } else {
      showNotification("No tagged snippets for this filter.", type = "warning")
    }
  })
  
  
  
  observeEvent(input$push_snippets_to_prompt, {
    removeModal()
    snippet_df <- previewed_snippets()
    snippet_texts <- snippet_df$context
    combined_context <- paste(snippet_texts, collapse = "\n---\n")
    chat_snippet_context(combined_context)
    showNotification("Snippets pushed to prompt context.", type = "message")
  })
  
  
  observeEvent(input$send_chat, {
    req(current_user(), input$chat_input, input$selected_model, input$chat_thread, db_path())
    
    disable("send_chat")
    showNotification("Model thinking...", type = "message")
    
    # Step 1: Save user message
    con <- dbConnect(RSQLite::SQLite(), db_path())
    on.exit(dbDisconnect(con), add = TRUE)
    ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    
    dbExecute(con, "INSERT INTO items (key, itemTypeID) VALUES (?, ?)",
              params = list(paste0("chat_user_", ts), -1))
    user_item_id <- dbGetQuery(con, "SELECT last_insert_rowid()")[[1]]
    
    dbExecute(con, "INSERT INTO itemTags (itemID, tagCategory, tagResponse, tagSource)
                  VALUES (?, 'item_type', 'chat', ?),
                         (?, 'chat_thread', ?, ?),
                         (?, 'sender', ?, ?),
                         (?, 'note_content', ?, ?),
                         (?, 'created_at', ?, ?)",
              params = c(
                user_item_id, current_user()$username,
                user_item_id, input$chat_thread, current_user()$username,
                user_item_id, current_user()$username, current_user()$username,
                user_item_id, input$chat_input, current_user()$username,
                user_item_id, ts, current_user()$username
              ))
    
    updateTextInput(session, "chat_input", value = "")
    shinyjs::click("refresh_chat_context")
    
    # Step 2: Build memory from prior messages
    load_full_history <- input$use_full_history
    k_last_messages <- input$k_last_messages
    
    memory_query <- "
    SELECT t.tagResponse
    FROM items i
    JOIN itemTags t ON i.itemID = t.itemID
    JOIN itemTags t2 ON i.itemID = t2.itemID
    WHERE t.tagCategory = 'note_content'
      AND t2.tagCategory = 'chat_thread'
      AND t2.tagResponse = ?
    ORDER BY i.itemID ASC
  "
    prior_messages <- dbGetQuery(con, memory_query, params = list(input$chat_thread))$tagResponse
    
    if (length(prior_messages) > 0) {
      if (!load_full_history) {
        prior_messages <- tail(prior_messages, k_last_messages)
      }
      memory_context <- paste(prior_messages, collapse = "\n\n---\n\n")
    } else {
      memory_context <- ""
    }
    
    # Step 3: Build prompt
    snippets <- chat_snippet_context() %||% ""
    prompt <- ""
    if (nchar(trimws(memory_context)) > 0) {
      prompt <- paste0("Previous conversation:\n", memory_context, "\n\n")
    }
    prompt <- paste0(prompt, current_user()$username, ":\n", input$chat_input)
    
    if (nchar(trimws(snippets)) > 0) {
      prompt <- paste(prompt, "\n\nHere is some info to help you think:\n", snippets)
    }
    
    # Step 4: Get model info
    entity_id <- dbGetQuery(con, "SELECT entity_id FROM entities WHERE entity_name = ? AND entity_type = 'model'",
                            params = list(input$selected_model))$entity_id[1]
    provider <- dbGetQuery(con, "SELECT tagValue FROM entity_tags WHERE entity_id = ? AND tagCategory = 'provider'",
                           params = list(entity_id))$tagValue[1]
    context_window <- as.integer(dbGetQuery(con, "SELECT tagValue FROM entity_tags WHERE entity_id = ? AND tagCategory = 'context_window'",
                                            params = list(entity_id))$tagValue[1])
    
    # Step 5: Generate (Ensure key for Gemini and OpenAI)
    response <- ""

    if (tolower(provider) == "huggingface" ) {
      if (!exists("hf_runner")) {
        hf_runner <<- reticulate::import_from_path("huggingface_model_runner", path = ".", convert = TRUE)
      }
      response <- hf_runner$generate_map_reduce_response(
        prompt = prompt,
        model_name = input$selected_model,
        context_window = context_window
      )
    }

    
    if (tolower(provider) == "google") {
      if (!exists("gem_runner")) {
        gem_runner <<- reticulate::import_from_path("gemini_model_runner", path = ".", convert = TRUE)
      }
      
      # Check if key exists
      user_key_check <- dbGetQuery(con, "
      SELECT tagValue FROM entity_tags
      WHERE entity_id = (
        SELECT entity_id FROM entities WHERE entity_name = ? AND entity_type = 'user'
      ) AND tagCategory = ?
    ", params = list(current_user()$username, paste0("api_path_", input$selected_model)))
      
      if (nrow(user_key_check) == 0) {
        showModal(modalDialog(
          title = paste("Enter API Key for", input$selected_model),
          passwordInput("new_api_key", "API Key:"),
          textInput("key_file_path", "Where should we save your API key?",
                    value = file.path(Sys.getenv("HOME"), paste0(".", input$selected_model, "_key.txt"))),
          checkboxInput("use_env_var", "Instead store as OS environment variable", FALSE),
          footer = tagList(modalButton("Cancel"), actionButton("save_api_key", "Save API Key"))
        ))
        enable("send_chat")
        return()
      }
      
      # Configure Gemini if needed
      api_key_path <- user_key_check$tagValue[1]
      gem_runner$configure_gemini(readLines(api_key_path, warn = FALSE))
      response <- gem_runner$run_gemini_chat(input$selected_model, prompt)
    }
    
    if (tolower(provider) == "openai") {
      # Look for the user-specific API key path
      user_key_check <- dbGetQuery(con, "
    SELECT tagValue FROM entity_tags
    WHERE entity_id = (
      SELECT entity_id FROM entities WHERE entity_name = ? AND entity_type = 'user'
    ) AND tagCategory = ?
  ", params = list(current_user()$username, paste0("api_path_", input$selected_model)))
      
      # If no API key path found, prompt user to enter it
      if (nrow(user_key_check) == 0) {
        showModal(modalDialog(
          title = paste("Enter API Key for", input$selected_model),
          passwordInput("new_api_key", "API Key:"),
          textInput("key_file_path", "Where should we save your API key?",
                    value = file.path(Sys.getenv("HOME"), paste0(".", input$selected_model, "_key.txt"))),
          checkboxInput("use_env_var", "Instead store as OS environment variable", FALSE),
          footer = tagList(modalButton("Cancel"), actionButton("save_api_key", "Save API Key"))
        ))
        enable("send_chat")
        return()
      }
      
      # Read the API key from file
      api_key_path <- user_key_check$tagValue[1]
      api_key <- readLines(api_key_path, warn = FALSE)
      
      # Call the OpenAI runner from sourced Python
      response <- tryCatch({
        openai_model_runner(
          prompt = prompt,
          model = input$selected_model,
          api_key = api_key,
          system_prompt = "You are a helpful assistant. Respond clearly and concisely.",
          temperature = 0.7,
          max_tokens = context_window
        )
      }, error = function(e) {
        showNotification(paste("OpenAI call failed:", e$message), type = "error")
        enable("send_chat")
        return(NULL)
      })
      
      if (is.null(response)) return()
    }
    
    
    # Step 6: Save model response
    ts2 <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    dbExecute(con, "INSERT INTO items (key, itemTypeID) VALUES (?, ?)",
              params = list(paste0("chat_bot_", ts2), -1))
    bot_item_id <- dbGetQuery(con, "SELECT last_insert_rowid()")[[1]]
    
    dbExecute(con, "INSERT INTO itemTags (itemID, tagCategory, tagResponse, tagSource)
                  VALUES (?, 'item_type', 'chat', ?),
                         (?, 'chat_thread', ?, ?),
                         (?, 'sender', ?, ?),
                         (?, 'note_content', ?, ?),
                         (?, 'created_at', ?, ?)",
              params = c(
                bot_item_id, input$selected_model,
                bot_item_id, input$chat_thread, input$selected_model,
                bot_item_id, input$selected_model, input$selected_model,
                bot_item_id, response, input$selected_model,
                bot_item_id, ts2, input$selected_model
              ))
    
    trigger_chat_history_update(trigger_chat_history_update() + 1)
    session$sendCustomMessage("highlight-code", list())
    
    enable("send_chat")
  })
  
  

  store__path <- function(db_path, username, provider, file_path) {
    key_hash <- digest::digest(readLines(file_path, warn = FALSE), algo = "sha256")
    
    con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    
    # Get the entity_id for the user
    entity_id <- DBI::dbGetQuery(con, "
    SELECT entity_id FROM entities WHERE entity_name = ? AND entity_type = 'user'
  ", params = list(username))$entity_id
    
    # Remove old entries
    DBI::dbExecute(con, "
    DELETE FROM entity_tags
    WHERE entity_id = ? AND tagCategory IN ('api_key_path', 'api_key_hash') AND tagSource = ?
  ", params = list(entity_id, provider))
    
    # Insert new path and hash
    DBI::dbExecute(con, "
    INSERT INTO entity_tags (entity_id, tagCategory, tagValue, tagSource)
    VALUES (?, 'api_key_path', ?, ?), (?, 'api_key_hash', ?, ?)
  ", params = list(entity_id, file_path, provider, entity_id, key_hash, provider))
    
    DBI::dbDisconnect(con)
    return(TRUE)
  }
  
  
  observeEvent(input$save_api_key, {
    req(input$new_api_key, input$key_file_path, current_user(), input$selected_model)
    
    if (input$use_env_var) {
      env_line <- paste0(toupper(input$selected_model), "_API_KEY='", input$new_api_key, "'\n")
      renviron_path <- file.path(Sys.getenv("HOME"), ".Renviron")
      write(env_line, file = renviron_path, append = TRUE)
      update <- "Saved to .Renviron"
    } else {
      writeLines(input$new_api_key, input$key_file_path)
      update <- paste("Key saved to", input$key_file_path)
    }
    
    con <- dbConnect(RSQLite::SQLite(), db_path())
    user_entity_id <- dbGetQuery(con, "
    SELECT entity_id FROM entities
    WHERE entity_name = ? AND entity_type = 'user'
  ", params = list(current_user()$username))$entity_id
    
    # Remove any prior keys
    dbExecute(con, "
    DELETE FROM entity_tags
    WHERE entity_id = ? AND tagCategory IN (?, ?)
  ", params = list(user_entity_id, 
                   paste0("api_path_", input$selected_model), 
                   paste0("api_hash_", input$selected_model)))
    
    # Insert key path
    dbExecute(con, "
    INSERT INTO entity_tags (entity_id, tagCategory, tagValue)
    VALUES (?, ?, ?)
  ", params = list(user_entity_id, 
                   paste0("api_path_", input$selected_model), 
                   input$key_file_path))
    
    # Insert key hash
    dbExecute(con, "
    INSERT INTO entity_tags (entity_id, tagCategory, tagValue)
    VALUES (?, ?, ?)
  ", params = list(user_entity_id, 
                   paste0("api_hash_", input$selected_model), 
                   digest::digest(input$new_api_key, algo = "sha256")))
    
    dbDisconnect(con)
    removeModal()
    showNotification(update, type = "message")
  })
  
  ##### Chat Response
  
  render_markdown <- function(markdown_text) {
    html <- commonmark::markdown_html(markdown_text)
    HTML(html)
  }
  
  
  output$conversation_history <- renderUI({
    req(db_path(), input$chat_thread, trigger_chat_history_update())
    
    con <- dbConnect(RSQLite::SQLite(), db_path())
    
    # Pull chat messages + sender tag
    query <- "
    SELECT
      it1.tagResponse AS note_content,
      it2.tagResponse AS sender,
      it3.tagResponse AS created_at
    FROM items i
    JOIN itemTags it1 ON i.itemID = it1.itemID AND it1.tagCategory = 'note_content'
    JOIN itemTags it2 ON i.itemID = it2.itemID AND it2.tagCategory = 'sender'
    JOIN itemTags it3 ON i.itemID = it3.itemID AND it3.tagCategory = 'created_at'
    JOIN itemTags thread ON i.itemID = thread.itemID
    WHERE thread.tagCategory = 'chat_thread' AND thread.tagResponse = ?
    ORDER BY created_at
  "
    chat_df <- dbGetQuery(con, query, params = list(input$chat_thread))
    dbDisconnect(con)
    
    if (nrow(chat_df) == 0) {
      return(HTML("<em>No messages yet.</em>"))
    }
    
    # Helper to render and sanitize markdown
    render_and_sanitize <- function(text) {
      raw_html <- commonmark::markdown_html(text)
      safe_html <- raw_html #htmltools::HTML(raw_html)
      return(safe_html)
    }
    
    # Construct chat bubbles
    chat_bubbles <- apply(chat_df, 1, function(row) {
      sender <- ifelse(is.na(row[["sender"]]), "Unknown", row[["sender"]])
      
      markdown_text <- row[["note_content"]]
      raw_html <- commonmark::markdown_html(markdown_text)
      content <-raw_html#  htmltools::HTML(raw_html)
      
      timestamp <- row[["created_at"]]
      class <- if (sender == current_user()$username) "user-message" else "bot-message"
      
      paste0("<div class='chat-bubble ", class, "'>",
             "<strong>", sender, ":</strong><br>", content,
             "<br><small>", timestamp, "</small></div>")
    })
    
    
    div(class = "chat-window", HTML(paste(chat_bubbles, collapse = "")))
    
    tags$script(HTML("
      setTimeout(function() {
        var chatWindow = document.querySelector('.chat-window');
        if (chatWindow) {
          chatWindow.scrollTop = chatWindow.scrollHeight;
        }
      }, 100);
    "))
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
