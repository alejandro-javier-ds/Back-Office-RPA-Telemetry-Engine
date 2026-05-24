import time
import logging
import pandas as pd
from sqlalchemy import create_engine, text
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager
import config

logging.basicConfig(
    level=logging.INFO,
    format='[%(levelname)s] %(asctime)s - %(message)s'
)

def get_sql_engine():
    return create_engine(config.get_connection_string(), fast_executemany=True)

def execute_rpa_pipeline(target_url: str, max_pages: int = 10, target_volume: int = 100000) -> None:
    start_time = time.time()
    extracted_data = []
    status = 'FAILED'
    
    chrome_options = Options()
    chrome_options.add_argument("--headless=new")
    chrome_options.add_argument("--disable-gpu")
    chrome_options.add_argument("--log-level=3")
    
    logging.info(f"PROCESS: Initializing headless WebDriver targeting {target_url}")
    
    try:
        service = Service(ChromeDriverManager().install())
        driver = webdriver.Chrome(service=service, options=chrome_options)
        wait = WebDriverWait(driver, 10)
        
        for page in range(1, max_pages + 1):
            page_url = f"{target_url}/page/{page}/"
            logging.info(f"PROCESS: Scraping payload from {page_url}")
            driver.get(page_url)
            
            wait.until(EC.presence_of_element_located((By.CLASS_NAME, "quote")))
            elements = driver.find_elements(By.CLASS_NAME, "quote")
            
            if not elements:
                logging.warning("PROCESS: End of pagination reached.")
                break
                
            for el in elements:
                text_content = el.find_element(By.CLASS_NAME, "text").text
                author = el.find_element(By.CLASS_NAME, "author").text
                try:
                    tags = el.find_element(By.CLASS_NAME, "tags").text
                except:
                    tags = "NONE"
                    
                extracted_data.append({
                    "Quote_Text": text_content,
                    "Author": author,
                    "Tags": tags
                })
                
        driver.quit()
        
        df_real = pd.DataFrame(extracted_data)
        
        if not df_real.empty:
            logging.info(f"TRANSFORM: Extracted {len(df_real)} real items. Multiplying payload to {target_volume} records...")
            df_massive = df_real.sample(n=target_volume, replace=True).reset_index(drop=True)
            
            logging.info("DATABASE: Executing Bulk Insert into RPA_Payload...")
            engine = get_sql_engine()
            with engine.begin() as conn:
                df_massive.to_sql('RPA_Payload', con=conn, if_exists='append', index=False, chunksize=20000)
                status = 'COMPLETED'
                logging.info(f"DATABASE: {len(df_massive)} records securely injected.")
        else:
            logging.error("SYSTEM_ERROR: No data extracted from the target.")
            df_massive = df_real
            
    except Exception as e:
        logging.error(f"SYSTEM_ERROR: Pipeline execution failure - {str(e)}")
        df_massive = pd.DataFrame()
        
    finally:
        end_time = time.time()
        duration = round(end_time - start_time, 2)
        items_processed = len(df_massive) if status == 'COMPLETED' else 0
        
        try:
            engine = get_sql_engine()
            with engine.begin() as conn:
                log_query = text("""
                    INSERT INTO RPA_Telemetry (TargetURL, ExecutionStatus, ItemsProcessed, DurationSeconds)
                    VALUES (:url, :status, :items, :duration)
                """)
                conn.execute(log_query, {
                    "url": target_url,
                    "status": status,
                    "items": items_processed,
                    "duration": duration
                })
            logging.info(f"SQL_SYNC: Telemetry registered successfully. Total time: {duration}s.")
        except Exception as db_error:
            logging.error(f"SYSTEM_ERROR: Database telemetry sync failure - {str(db_error)}")

if __name__ == "__main__":
    logging.info("Initializing Enterprise RPA Pipeline")
    execute_rpa_pipeline("https://quotes.toscrape.com", max_pages=10, target_volume=100000)