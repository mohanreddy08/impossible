from fastapi import Query

LIMIT = Query(50, ge=1, le=200, description="Page size (max 200)")
OFFSET = Query(0, ge=0, description="Number of items to skip")
