-- ============================================================================
-- Padrón inicial del depósito Virgilio. Ajustar por depósito.
-- El correo es la identidad y no puede repetirse entre dos personas.
-- ============================================================================
insert into fichada.empleados (legajo, nombre, correo, empresa) values
  ('8',   'Farias Juan Hilario', 'juanhfarias69@gmail.com',          'Chef'),
  ('94',  'Tevez Isidro',        'isidrotevez55@gmail.com',          'Chef'),
  ('104', 'Moncayo Jhonny',      'johnnyjahel@hotmail.com',          'Chef'),
  ('118', 'Becker Marianela',    'marianelalbecker@gmail.com',       'Chef'),
  ('237', 'Ortiz Franco',        'francoortiz01.fo@gmail.com',       'Loeke'),
  ('277', 'Cartaya Jhonny',      'jhonnyjosecartayaperez@gmail.com', 'Loeke')
on conflict do nothing;
