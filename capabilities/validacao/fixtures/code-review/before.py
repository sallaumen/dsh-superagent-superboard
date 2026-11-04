def eligible_suppliers(capabilities, variant_id, destination):
    return [
        item["supplier_id"]
        for item in capabilities
        if item["active"]
        and item["variant_id"] == variant_id
        and destination in item["destinations"]
    ]
