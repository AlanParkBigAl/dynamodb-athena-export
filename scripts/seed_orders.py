#!/usr/bin/env python3
"""Load fake orders into the DynamoDB table so there is something to export and query.

Usage:
    python scripts/seed_orders.py --table Orders --count 500 --region ap-southeast-2
"""

import argparse
import random
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import boto3

STATUSES = ["PENDING", "PAID", "SHIPPED", "DELIVERED", "CANCELLED"]


def make_order(customer_ids):
    created = datetime.now(timezone.utc) - timedelta(
        days=random.randint(0, 30), minutes=random.randint(0, 1440)
    )
    return {
        "OrderId": str(uuid.uuid4()),
        "CustomerId": random.choice(customer_ids),
        "Status": random.choices(STATUSES, weights=[10, 30, 25, 30, 5])[0],
        "OrderTotal": Decimal(str(round(random.uniform(5, 500), 2))),
        "CreatedAt": created.isoformat(timespec="seconds"),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--table", default="Orders")
    parser.add_argument("--count", type=int, default=500)
    parser.add_argument("--region", default="ap-southeast-2")
    args = parser.parse_args()

    table = boto3.resource("dynamodb", region_name=args.region).Table(args.table)
    customer_ids = [f"CUST-{i:04d}" for i in range(1, 51)]

    with table.batch_writer() as batch:
        for _ in range(args.count):
            batch.put_item(Item=make_order(customer_ids))

    print(f"Wrote {args.count} orders to {args.table}")


if __name__ == "__main__":
    main()
