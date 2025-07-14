INSERT INTO "language" (name, descr) 
    VALUES 
        ('en', 'English'),
        ('fr', 'French');

INSERT INTO template_engine (name, descr) 
    VALUES 
        ('go-template', 'A Go template for dynamic content generation');

INSERT INTO template_status (name, descr) 
    VALUES 
        ('draft', 'Template is in draft mode'),
        ('published', 'Template is ready to be used');

INSERT INTO section_type (name, seq, descr) 
    VALUES 
        ('header', 10, 'Header section'),
        ('body', 20, 'Body section'),
        ('footer', 30, 'Footer section');

INSERT INTO variable_type (name, data_type)
    VALUES
      ('INTEGER','INTEGER'),
      ('TEXT','TEXT'),
      ('INTEGER_RANGE','INT4RANGE'),
      ('INTERVAL','INTERVAL'),
      ('BOOLEAN','BOOLEAN'),
      ('TEXT_LIST','TEXT[]'),
      ('INTEGER_LIST','INT[]'),
      ('DATERANGE','DATERANGE'),
      ('TSTZRANGE','TSTZRANGE');
