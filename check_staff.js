const url = 'https://ldrvghqibwlzfxvvignu.supabase.co';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcnZnaHFpYndsemZ4dnZpZ251Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1NTA2MDYsImV4cCI6MjEwMjEyNjYwNn0.XrhMQo07mefgvyhIYFaA6BmgVXLdFlwZmQPHUWFjDRg';

async function main() {
  const res = await fetch(url + '/rest/v1/staff?select=*', {
    headers: { 'apikey': key, 'Authorization': 'Bearer ' + key }
  });
  console.log(await res.json());
}
main();
