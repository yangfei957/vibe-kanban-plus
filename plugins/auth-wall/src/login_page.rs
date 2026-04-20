/// Embedded login page HTML — standalone, no React/JS framework dependency.
pub const LOGIN_PAGE_HTML: &str = r##"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Login — Vibe Kanban</title>
<style>
  *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
  body{
    font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;
    background:#0f172a;color:#e2e8f0;
    display:flex;align-items:center;justify-content:center;
    min-height:100vh;
  }
  .card{
    background:#1e293b;border-radius:12px;padding:2.5rem;
    width:100%;max-width:400px;box-shadow:0 25px 50px -12px rgba(0,0,0,.5);
  }
  .logo{text-align:center;margin-bottom:1.5rem}
  .logo svg{width:48px;height:48px;fill:#818cf8}
  h1{text-align:center;font-size:1.5rem;font-weight:600;margin-bottom:.25rem}
  .subtitle{text-align:center;color:#94a3b8;font-size:.875rem;margin-bottom:2rem}
  label{display:block;font-size:.875rem;color:#94a3b8;margin-bottom:.375rem}
  .input-wrapper{position:relative;margin-bottom:1.25rem}
  input[type=password]{
    width:100%;padding:.75rem 2.75rem .75rem .75rem;
    background:#0f172a;border:1px solid #334155;border-radius:8px;
    color:#e2e8f0;font-size:1rem;outline:none;transition:border-color .2s;
  }
  input[type=password]:focus{border-color:#818cf8}
  .toggle-pw{
    position:absolute;right:.75rem;top:50%;transform:translateY(-50%);
    background:none;border:none;color:#64748b;cursor:pointer;font-size:1.1rem;
    display:flex;align-items:center;
  }
  .toggle-pw:hover{color:#94a3b8}
  button[type=submit]{
    width:100%;padding:.75rem;background:#6366f1;color:#fff;
    border:none;border-radius:8px;font-size:1rem;font-weight:600;
    cursor:pointer;transition:background .2s;
  }
  button[type=submit]:hover{background:#4f46e5}
  button[type=submit]:disabled{background:#475569;cursor:not-allowed}
  .alert{
    padding:.75rem 1rem;border-radius:8px;font-size:.875rem;
    margin-bottom:1rem;display:none;
  }
  .alert-error{background:#450a0a;border:1px solid #991b1b;color:#fca5a5}
  .alert-warn{background:#451a03;border:1px solid #92400e;color:#fed7aa}
  .alert-info{background:#0c4a6e;border:1px solid #0369a1;color:#bae6fd}
  .footer{text-align:center;margin-top:1.5rem;font-size:.65rem;color:#475569}
  .footer code{background:#0f172a;padding:2px 6px;border-radius:4px;font-family:monospace;color:#64748b}
</style>
</head>
<body>
<div class="card">
  <div class="logo">
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
      <path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zM12 17c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1s3.1 1.39 3.1 3.1v2z"/>
    </svg>
  </div>
  <h1>Vibe Kanban</h1>
  <p class="subtitle">Please enter your password to continue</p>

  <div id="alert" class="alert"></div>

  <form id="login-form" autocomplete="off">
    <label for="password">Password</label>
    <div class="input-wrapper">
      <input type="password" id="password" name="password"
             placeholder="Enter your password" required autofocus>
      <button type="button" class="toggle-pw" id="toggle-pw" aria-label="Toggle password visibility">
        <span id="eye-icon">👁</span>
      </button>
    </div>
    <button type="submit" id="submit-btn">Sign In</button>
  </form>

  <div class="footer">
    Protected by Auth Wall Plugin<br>
    Logout: <code>/auth-wall/api/logout</code>
  </div>
</div>

<script>
(function(){
  const form = document.getElementById('login-form');
  const pwInput = document.getElementById('password');
  const submitBtn = document.getElementById('submit-btn');
  const alertBox = document.getElementById('alert');
  const togglePw = document.getElementById('toggle-pw');
  const eyeIcon = document.getElementById('eye-icon');

  togglePw.addEventListener('click', function(){
    const isPassword = pwInput.type === 'password';
    pwInput.type = isPassword ? 'text' : 'password';
    eyeIcon.textContent = isPassword ? '🙈' : '👁';
  });

  function showAlert(msg, type){
    alertBox.className = 'alert alert-' + type;
    alertBox.textContent = msg;
    alertBox.style.display = 'block';
  }

  form.addEventListener('submit', async function(e){
    e.preventDefault();
    const password = pwInput.value;
    if(!password){ showAlert('Please enter a password.','warn'); return; }

    submitBtn.disabled = true;
    submitBtn.textContent = 'Signing in…';
    alertBox.style.display = 'none';

    try {
      const res = await fetch('/auth-wall/api/login', {
        method: 'POST',
        headers: {'Content-Type':'application/json'},
        body: JSON.stringify({ password: password })
      });
      const data = await res.json();

      if(res.ok && data.success){
        showAlert('Login successful! Redirecting…','info');
        setTimeout(function(){ window.location.href = '/'; }, 500);
      } else {
        showAlert(data.message || 'Login failed.', res.status === 429 ? 'warn' : 'error');
        pwInput.value = '';
        pwInput.focus();
      }
    } catch(err) {
      showAlert('Network error. Please try again.','error');
    } finally {
      submitBtn.disabled = false;
      submitBtn.textContent = 'Sign In';
    }
  });
})();
</script>
</body>
</html>
"##;
