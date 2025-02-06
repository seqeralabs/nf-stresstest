The `fusion_test.db` is a sqlite3 DB of the format: 

```console
60002  Nextflow!
```

It was created with a python snippet:

```python
import sqlite3
import random

# Connect to the database
conn = sqlite3.connect('fusion_test.db')
cursor = conn.cursor()

# Define the values
values = ['Nextflow!', 'Fusion!', 'MultiQC!', 'Wave!', 'Containers!', 'Science!']

data = [ (random.choice(values),) for _ in range(1000000) ]  # Randomly shuffled

# Execute bulk insert
cursor.executemany("INSERT INTO TASKS (name) VALUES (?)", data)

# Commit and close
conn.commit()
conn.close()
```