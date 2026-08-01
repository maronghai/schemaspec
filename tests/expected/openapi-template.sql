{
  "openapi": "3.1.0",
  "info": {
    "title": "app",
    "version": "0.68.0"
  },
  "paths": {},
  "components": {
    "schemas": {
      "users": {
        "type": "object",
        "properties": {
          "id": {"type":"integer"},
          "created_at": {"type":"string","format":"date-time"},
          "updated_at": {"type":"string","format":"date-time"},
          "name": {"type":"string","maxLength":32},
          "email": {"type":"string","maxLength":128}
        },
        "required": ["name", "email"],
        "additionalProperties": false
      },
      "orders": {
        "type": "object",
        "properties": {
          "id": {"type":"integer"},
          "created_at": {"type":"string","format":"date-time"},
          "updated_at": {"type":"string","format":"date-time"},
          "amount": {"type":"number","multipleOf":0.01}
        },
        "required": ["amount"],
        "additionalProperties": false
      }    }
  }
}
