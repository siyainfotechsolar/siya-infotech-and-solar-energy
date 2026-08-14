const url = 'https://ldrvghqibwlzfxvvignu.supabase.co';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcnZnaHFpYndsemZ4dnZpZ251Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1NTA2MDYsImV4cCI6MjEwMjEyNjYwNn0.XrhMQo07mefgvyhIYFaA6BmgVXLdFlwZmQPHUWFjDRg';

async function main() {
  const headers = { 'apikey': key, 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' };
  
  console.log('Signing up...');
  const res = await fetch(url + '/auth/v1/signup', {
    method: 'POST',
    headers,
    body: JSON.stringify({ email: 'admin@siyasolar.com', password: 'password123' })
  });
  
  const data = await res.json();
  if (!data.user || !data.user.id) {
    console.error('Failed to create user:', data);
    return;
  }
  
  const userId = data.user.id;
  console.log('User created:', userId);
  
  const staffRes = await fetch(url + '/rest/v1/staff', {
    method: 'POST',
    headers: { ...headers, 'Prefer': 'return=representation' },
    body: JSON.stringify({ id: userId, name: 'System Admin', role: 'admin', status: 'active' })
  });
  
  const staffData = await staffRes.json();
  console.log('Staff inserted:', staffData);
}

main();
