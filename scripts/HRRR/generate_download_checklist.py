# generate_download_checklist.py
import pandas as pd
import sys
import numpy as np
import os

date_str = sys.argv[1]

year_str = date_str[0:4]
month_str = date_str[4:6]
day_str = date_str[6:8]

df_day = pd.DataFrame(data = [f'{year_str}-{month_str}-{day_str}'],
                      columns = ['download_date'])
df_day['download_date'] = pd.to_datetime(df_day['download_date'])

if not os.path.exists('./wus_hrrr_daily_download_checklist.csv'):
    df_day.to_csv('./wus_hrrr_daily_download_checklist.csv',index = False)
else:
    df = pd.read_csv('./wus_hrrr_daily_download_checklist.csv')
    df['download_date'] = pd.to_datetime(df['download_date'])

    pd.concat([df,df_day]).to_csv('./wus_hrrr_daily_download_checklist.csv',index = False)
    