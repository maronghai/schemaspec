{
  "openapi": "3.1.0",
  "info": {
    "title": "myapp",
    "version": "0.68.0"
  },
  "paths": {},
  "components": {
    "schemas": {
      "users": {
        "type": "object",
        "properties": {
          "id": {"type":"integer"},
          "name": {"type":"string","maxLength":32},
          "email": {"type":"string","maxLength":128},
          "status": {"type":"string","enum":["active","inactive"]}
        },
        "required": ["name", "email"],
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
