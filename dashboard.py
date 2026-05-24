import streamlit as st
import pandas as pd
from sqlalchemy import create_engine
import config
from engine.bot_core import execute_rpa_pipeline

st.set_page_config(page_title="RPA Telemetry Hub", layout="wide")

def get_sql_engine():
    return create_engine(config.get_connection_string())

@st.cache_data(ttl=30)
def fetch_telemetry():
    engine = get_sql_engine()
    try:
        return pd.read_sql("SELECT * FROM RPA_Telemetry ORDER BY ExecutionDate DESC", engine)
    except:
        return pd.DataFrame()

@st.cache_data(ttl=30)
def fetch_payload(limit=500):
    engine = get_sql_engine()
    try:
        # Traemos solo los últimos 500 registros para no saturar la UI web
        return pd.read_sql(f"SELECT TOP {limit} * FROM RPA_Payload ORDER BY Extracted_At DESC", engine)
    except:
        return pd.DataFrame()

def main():
    st.markdown("""
        <style>
        .main-header { font-size: 2.2rem; font-weight: 800; color: #1e3a8a; margin-bottom: 0;}
        .sub-header { font-size: 1.1rem; color: #64748b; margin-bottom: 2rem;}
        </style>
    """, unsafe_allow_html=True)

    st.markdown('<p class="main-header">Enterprise RPA Control Center</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-header">Back-Office Telemetry & Distributed Payload Hub</p>', unsafe_allow_html=True)

    with st.sidebar:
        st.title("Orquestador RPA")
        st.markdown("---")
        target_url = st.text_input("Target URL", value="https://quotes.toscrape.com")
        pages_to_scrape = st.slider("Pages to Scrape", 1, 10, 10)
        synthetic_volume = st.number_input(
            "Target Volume (Synthetic)", 
            min_value=1000, 
            max_value=500000, 
            value=100000, 
            step=10000
        )

        if st.button("Initialize RPA Pipeline", type="primary", use_container_width=True):
            with st.spinner(f"Extrayendo y multiplicando a {synthetic_volume:,} registros..."):
                execute_rpa_pipeline(target_url, max_pages=pages_to_scrape, target_volume=synthetic_volume)
            st.success("Pipeline Execution Completed!")
            st.cache_data.clear()
            st.rerun()
            
        st.markdown("---")
        st.info("System strictly enforces SSOT (Single Source of Truth). Data is injected directly into SQL Server, bypassing local files.")

    df_telemetry = fetch_telemetry()
    df_payload = fetch_payload()

    if not df_telemetry.empty:
        total_runs = len(df_telemetry)
        total_items = df_telemetry['ItemsProcessed'].sum()
        avg_duration = df_telemetry['DurationSeconds'].mean()

        col1, col2, col3 = st.columns(3)
        col1.metric("Total Executions", f"{total_runs}")
        col2.metric("Total Items Extracted", f"{total_items:,}")
        col3.metric("Avg Execution Time", f"{avg_duration:.2f} s")
    else:
        st.warning("No telemetry data found. Initialize the pipeline to start.")

    st.markdown("<br>", unsafe_allow_html=True)

    tab_telemetry, tab_payload = st.tabs(["Telemetry Logs (RPA Health)", "Serialized Payload (Data Lake)"])

    with tab_telemetry:
        st.markdown("#### Execution History")
        st.dataframe(df_telemetry, use_container_width=True, height=400)

    with tab_payload:
        st.markdown(f"#### Extracted Data (Showing top {len(df_payload)} recent records)")
        st.dataframe(df_payload, use_container_width=True, height=400)

if __name__ == "__main__":
    main()