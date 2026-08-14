const url = 'https://ldrvghqibwlzfxvvignu.supabase.co';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcnZnaHFpYndsemZ4dnZpZ251Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1NTA2MDYsImV4cCI6MjEwMjEyNjYwNn0.XrhMQo07mefgvyhIYFaA6BmgVXLdFlwZmQPHUWFjDRg';

async function main() {
  const headers = { 'apikey': key, 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' };
  const res = await fetch(url + '/auth/v1/token?grant_type=password', {
    method: 'POST',
    headers,
    body: JSON.stringify({ email: 'admin@siyasolar.com', password: 'password123' })
  });
  console.log(await res.json());
}
main();
