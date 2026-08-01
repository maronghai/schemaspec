-- Oracle multi-word types and precision/scale
CREATE TABLE measurements (
  id NUMBER(10) NOT NULL,
  temperature NUMBER(5,2) DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  active NUMBER(1) DEFAULT 1,
  PRIMARY KEY (id)
);
