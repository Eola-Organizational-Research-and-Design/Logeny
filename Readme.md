# Logeny Basic - Setup and Usage Guide

## Description

The Logeny Semantic Knowledge Hub is a tool that helps users manage and interact with a collection of documents and information. It provides features for:

-   Synchronizing a folder with a local database.
-   Searching documents using semantic search.
-   Classifying text using machine learning models.
-   Chatting with language models to get answers and insights.
-   Viewing various file types.
-   Collaboration through project notes and user management.

This document guides you through setting up and running the application.

## Prerequisites

Before running the application, you need to have the following software installed:

-   **R:** Please download and install R from the official website: <https://www.r-project.org/>
    -   **Adding R to your System's PATH (Windows):**
        1.  **Locate R's `bin` directory:** After installing R, find the directory containing `Rscript.exe`. This is usually in a location like `C:\Program Files\R\R-x.x.x\bin` (replace `x.x.x` with your R version).
        2.  **Open Environment Variables:**
            -   Press `Win + R`, type `sysdm.cpl`, and press Enter.
            -   Go to the "Advanced" tab and click "Environment Variables...".
        3.  **Edit the PATH variable:**
            -   In the "System variables" section, find and select the "Path" variable, then click "Edit...".
            -   Click "New" and add the full path to the R `bin` directory you found in step 1.
            -   Click "OK" on all windows to save the changes.
        4.  **Restart Command Prompt:** Close and reopen any command prompt windows for the changes to take effect.
	5.  ** Run Logeny_Install.bat to install the basic R packages needed to run the app.


-   **Python:** (Optional) Logeny leverages python for machine learning computations. We check for a Python installation in when you first run the app. If that does not work download and install Python 3.x (preferably the latest version) from the official website: <https://www.python.org/downloads/>
    -   Ensure that Python is added to your system's PATH environment variable.



## Running the Application (clickable)

1.  **Navigate to the project directory (if you're not already there):** 
2.  **Run the application:**
    -   Double click the `Logeny Basic.bat` file.
    -   This script will launch the Shiny application in your default web browser, and a command prompt window in the backround.
	- 	Do not close the command prompt until you are ready to terminate the application. This is where errors and other system messages will print.



## Running the Application (command prompt)

1.  **Navigate to the project directory (if you're not already there):** Open your command prompt or terminal and use the `cd` command to navigate to the directory containing `Logeny Basic.bat`.
2.  **Run the application:**
    -   Execute the `Logeny Basic.bat` file.
    -   This script will launch the Shiny application in your default web browser.

## Using the Application

### Login

-   **Enter Project Folder:** On the initial screen, you'll be prompted to enter the path to the folder containing your documents. 
	-   As a defulet we created a subfolder named "document library" in the same directory as this application where you may place your documents there. 
	-   You can, however, specify any folder you wish. The application will create or connect to a local SQLite database in this folder to store document metadata and processing results.
-   **Connect or Create DB:** Click the "Connect or Create DB" button.
    -   If a database exists in the specified folder, you'll be presented with login and registration options.
    -   If no database exists, you'll be prompted to create an admin user.
-   **Admin Creation:** If creating a new database, enter an admin username and password and click "Create Admin."
-   **Login:** If a database already exists, enter your username and password and click "Login."
-   **Register:** If you don't have an account, enter a new username and password and click "Request Access." Your request will be pending admin approval.

### Main Application Tabs

Once logged in, you'll see the main application interface with several tabs:

-   **Sync Folder:**
    -   **Refresh DB:** Re-sync your document folder with the local database. 
			- The application automatically updates the database when changes are made to the folder, but this button can be used to manually force a refresh. 
			- This process scans the folder and updates the database with any changes (new files, modified files, deleted files). To add documents, simply place them in the specified folder. 
			- Try refreshing the DB as a first step to troubleshooting any in app problems (such as failed semantic search)
    -   **Generate Embeddings:** You must create embeddings of you documents to make them searchable. 
			- This is a computationally intensive process that needs to be done after initially connecting to the database or after adding or modifying documents in the project folder.
			- Your document is split into chunks, and an embedding is created for each chunk. We can then scan for these embeddings numerically. 
	-   **Chunk Size:** Set the size (in words) of text chunks when generating embeddings. Smaller chunks may provide more granular search results but increase processing time.
    -   **Model Name:** Choose the sentence transformer model used to generate document embeddings. Different models may provide different search accuracy. The default is a good general-purpose model. Alternative models from Hugging face should work too. 
-   **Collections:**
    -   View items within collections in your database. A collection could represent a folder or a specific group of documents within the project folder.
-   **Search Collection:**
    -   This function perform semantic searches on your documents, looking for documnet chunks with similar meaining to your prompt.
        -   **Enter Search Term:** Type in the word or phrase you want to search for.
        -   **Number of Results:** Specify the number of search results you want to retrieve.
        -   **Run Semantic Search:** Click this button to perform the search. The search is performed locally using a custom vector database library. Search speed may be limited by your computer's processing power and the size of your document collection. Consider a high-performance computing setup for faster search if dealing with very large datasets.
        -   **Tagging Snippets:** The search results table allows you to tag snippets. You can add tags to categorize or label specific snippets for later use. Click the "Tag" button to add a tag. You'll be prompted to enter a "Tag Category" and a "Tag Value". These tags can be used to filter or provide context in other parts of the application.
-   **Text Classification:**
    -   Classify text data using a machine learning model.
        -   **Select Column to Classify:** Choose the column in your data that contains the text you want to classify.
        -   **Classifier Tag:** Enter a tag to identify the classification you are performing (e.g., "sentiment", "topic").
        -   **Classification Prompt:** Write a prompt that instructs the model on how to classify the text.
        -   **Classification Terms:** Enter a comma-separated list of terms that the model should use for classification (e.g., "positive, negative, neutral").
        -   **Run Classification:** Click this button to perform the classification.
        -   **Show Pre-classification Filters:** Optionally filter the data before classification using query terms, collection names, or date ranges.
        -   **Show Example Tag Filters:** Optionally filter and preview example snippets based on existing tags to use as context for the classification prompt. Tags created in the "Search Collection" tab can be used here.
        -   **Preview Example Snippets:** Preview the snippets that match your example tag filters.
        -   The results of the classification will be displayed in a table.
-   **Chat with Model:**
    -   Interact with a language model.
        -   **Choose a Model:** Select the language model you want to use for the chat.
            -   **Important:** Using the Gemini or OpenAI models require you to acquire an Gemini API key from Google, or a OpenAI API key. 
				- Please refer to Google's documentation for instructions on obtaining an API key and for insights on their free tier. (https://ai.google.dev/gemini-api/docs/api-key).
				- OpenAI keys can be optained here: https://platform.openai.com/api-keys.
            -   Hugging Face models included in the app's default model list and are free to use but may take some time to download on their first use. The model files are cached locally after the initial download, so subsequent uses will be faster.
        -   **Select Thread/Start New Thread:** Choose an existing chat thread or start a new one to organize your conversations. (You may call differnt models within the same conversation).
        -   **Grounding Interface:** Control how much of the conversation history and which tagged snippets are included as context for the model. This is important for providing the model with relevant information. 
        -   **Show Chat Filters:** Optionally filter and preview tagged snippets to provide context for the model's responses. Tags created in the "Search Collection" tab can be used here.
        -   **Include Collection Documents:** Optionally include specific documents from your collection as context for the model.
-   **File Viewer:**
    -   Preview various file types directly within the application.
-   **Teams:**
    -   Collaborate with other users through project notes.

## Troubleshooting

-   **R or Python Not Found:** Ensure that R and Python are correctly installed and added to your system's PATH environment variable. See the "Prerequisites" section for detailed instructions on adding R to the PATH (Windows).

-   **Python Dependency Errors:** If you encounter errors during the Python dependency installation, try updating `pip` and `setuptools`:

    ``` bash
    python -m pip install --upgrade pip setuptools
    ```

-   **Hugging Face Model Download Issues:** If you experience slow downloads or connection issues when using Hugging Face models, check your internet connection and ensure you have enough disk space. We attempt to download and install these models for you but, current functioanlity for huggingface models varies accross users.

-   **Semantic Search Performance:** Semantic search is performed locally and may be slow for large document collections. 
		- To help with this we apply document serach only to the subcollection currently displayed in the "Collections" tab 
		- Consider splitting your collection into subfolders to enhance search percision, or moving your workload into high-performance computing setup for faster search if dealing with very large datasets.
		- Semantic search will occastioanlly fail due to library updating issues. Try refershing the database if you are not receiving search results. Clicking "show previous search results" will often help too. 

-   **API Key:** The "Chat with Model" feature may require you to obtain and configure an API key for the listed commercial models. 
		- In the cureent setup you must enter an API key the first time you use a model, even if the model is offered by the same provider. However, you may use the same API key accross a provider's models. 

## Support

For support, please contact: [ayenda\@eolaord.com](mailto:ayenda@eolaord.com)

## Support Logeny Basic

This version of Logeny Basic is offered as a pay-what-you-can service. If you find it useful, please consider supporting its development:

<https://ko-fi.com/logeny#>

## Copyright

Copyright © 2024 Eola Organizational Research and Design LLC
