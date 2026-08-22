-- Add payment_type column to customers and leads tables
ALTER TABLE customers ADD COLUMN IF NOT EXISTS payment_type VARCHAR DEFAULT 'CASH';
ALTER TABLE leads ADD COLUMN IF NOT EXISTS payment_type VARCHAR DEFAULT 'CASH';

-- Initialize payment_type for existing records based on loan_required
UPDATE customers SET payment_type = 'LOAN' WHERE loan_required = true;
UPDATE customers SET payment_type = 'CASH' WHERE loan_required = false OR loan_required IS NULL;
