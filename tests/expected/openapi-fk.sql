{
  "openapi": "3.1.0",
  "info": {
    "title": "shop",
    "version": "0.59.0"
  },
  "paths": {},
  "components": {
    "schemas": {
      "users": {
        "type": "object",
        "properties": {
          "id": {"type":"integer"},
          "name": {"type":"string","maxLength":32}
        },
        "required": ["name"],
        "additionalProperties": false
      },
      "orders": {
        "type": "object",
        "properties": {
          "id": {"type":"integer"},
          "user_id": {
            "$ref": "#/components/schemas/users",
            "description": "Foreign key to users"
          },
          "amount": {"type":"number","multipleOf":0.01}
        },
        "required": ["amount"],
        "additionalProperties": false
      }    }
  }
}
