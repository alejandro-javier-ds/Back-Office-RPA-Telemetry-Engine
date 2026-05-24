import os

SERVER_NAME = os.getenv("DB_SERVER", r"(localdb)\MSSQLLocalDB")
DATABASE_NAME = os.getenv("DB_NAME", "RPADatabase")

def get_connection_string() -> str:
    return f"mssql+pyodbc://@{SERVER_NAME}/{DATABASE_NAME}?driver=ODBC+Driver+17+for+SQL+Server&Trusted_Connection=yes"