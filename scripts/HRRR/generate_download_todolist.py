# generate_download_todolist.py
import pandas as pd
import sys
import numpy as np

year_str = sys.argv[1]
month_str = sys.argv[2]
day_str = sys.argv[3]
directory = sys.argv[4]


df = pd.read_csv('./wus_hrrr_daily_download_checklist.csv')
last_date_str = df['download_date'].iloc[-1]
current_date_str = f'{year_str}-{month_str}-{day_str}'

date_range = np.arange(np.datetime64(last_date_str), np.datetime64(current_date_str) + np.timedelta64(1, "D"), np.timedelta64(1, "D"))
lst = []
for i in range(1,len(date_range)):
    lst.append([str(date_range[i]).replace('-',''),directory])
df_todo = pd.DataFrame(lst,columns = ['date','directory'])

df_todo.to_csv('./wus_hrrr_daily_download_todo.csv',index = False)

