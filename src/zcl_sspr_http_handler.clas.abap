CLASS zcl_sspr_http_handler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_http_extension .

  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS:
      handle_landing_page
        IMPORTING server TYPE REF TO if_http_server,

      handle_request_token
        IMPORTING server TYPE REF TO if_http_server,

      handle_token_action
        IMPORTING server TYPE REF TO if_http_server
                  token  TYPE string,

      handle_confirm_unlock
        IMPORTING server TYPE REF TO if_http_server,

      handle_set_password
        IMPORTING server TYPE REF TO if_http_server,

      validate_and_load_token
        IMPORTING server          TYPE REF TO if_http_server
                  raw_token       TYPE string
                  expected_action TYPE string OPTIONAL
        EXPORTING token_hash      TYPE zsspr_tokens-token
                  token_rec       TYPE zsspr_tokens
                  is_valid        TYPE abap_bool,

      render_response
        IMPORTING server       TYPE REF TO if_http_server
                  status_code  TYPE i DEFAULT 200
                  content_type TYPE string DEFAULT 'text/html; charset=utf-8'
                  body         TYPE string,

      render_page
        IMPORTING title       TYPE string
                  card_title  TYPE string
                  card_sub    TYPE string OPTIONAL
                  content     TYPE string
        RETURNING VALUE(html) TYPE string,

      render_message_page
        IMPORTING server      TYPE REF TO if_http_server
                  title       TYPE string
                  type        TYPE string " 'success', 'error', 'info', 'warning'
                  heading     TYPE string
                  message     TYPE string
                  detail      TYPE string OPTIONAL
                  show_home   TYPE abap_bool DEFAULT abap_true
                  status_code TYPE i DEFAULT 200,

      is_same_origin_post
        IMPORTING server        TYPE REF TO if_http_server
        RETURNING VALUE(is_ok)  TYPE abap_bool,

      is_trusted_proxy_ip
        IMPORTING ip_str          TYPE string
        RETURNING VALUE(trusted)  TYPE abap_bool,

      increment_token_attempts
        IMPORTING token_hash      TYPE zsspr_tokens-token
        RETURNING VALUE(attempts) TYPE i,

      render_password_form
        IMPORTING server   TYPE REF TO if_http_server
                  token    TYPE string
                  bname    TYPE bapibname-bapibname
                  err_msg  TYPE string OPTIONAL,

      render_unlock_form
        IMPORTING server TYPE REF TO if_http_server
                  token  TYPE string
                  bname  TYPE bapibname-bapibname,

      generate_secure_token
        RETURNING VALUE(token) TYPE string,

      hash_token
        IMPORTING token             TYPE string
        RETURNING VALUE(token_hash) TYPE zsspr_tokens-token,

      is_production_system
        RETURNING VALUE(is_prod) TYPE abap_bool,

      get_client_ip
        IMPORTING server        TYPE REF TO if_http_server
        RETURNING VALUE(ip_str) TYPE string,

      get_base_url
        IMPORTING server         TYPE REF TO if_http_server
        RETURNING VALUE(url_str) TYPE string,

      is_protected_account
        IMPORTING bname            TYPE bapibname-bapibname
        RETURNING VALUE(protected) TYPE abap_bool,

      send_notification_email
        IMPORTING VALUE(recipient_email) TYPE csequence
                  VALUE(subject)         TYPE csequence
                  VALUE(html_content)    TYPE string
        RETURNING VALUE(sent_ok)         TYPE abap_bool,

      get_user_email_and_name
        IMPORTING bname           TYPE bapibname-bapibname
        EXPORTING email           TYPE string
                  fullname        TYPE string
                  user_found      TYPE abap_bool
                  is_dialog       TYPE abap_bool
                  is_locked       TYPE abap_bool
                  is_admin_locked TYPE abap_bool
                  is_expired      TYPE abap_bool,

      mask_email
        IMPORTING email         TYPE string
        RETURNING VALUE(masked) TYPE string.

ENDCLASS.



CLASS ZCL_SSPR_HTTP_HANDLER IMPLEMENTATION.


  METHOD if_http_extension~handle_request.
    DATA: lv_method TYPE string,
          lv_token  TYPE string,
          lv_action TYPE string.

    lv_method = to_upper( server->request->get_header_field( '~request_method' ) ).
    lv_token  = server->request->get_form_field( 'token' ).
    lv_action = server->request->get_form_field( 'action' ).

    IF lv_method = 'POST'.
      IF me->is_same_origin_post( server ) = abap_false.
        me->render_message_page(
          server      = server
          title       = 'Forbidden'
          type        = 'error'
          heading     = 'Cross-Site Request Blocked'
          message     = 'This request was rejected for security reasons. Please submit directly from the self-service portal.'
          show_home   = abap_true
          status_code = 403 ).
        RETURN.
      ENDIF.

      IF lv_action = 'request_token'.
        me->handle_request_token( server ).
      ELSEIF lv_action = 'set_password'.
        me->handle_set_password( server ).
      ELSEIF lv_action = 'confirm_unlock'.
        me->handle_confirm_unlock( server ).
      ELSE.
        me->render_message_page(
          server      = server
          title       = 'Invalid Request'
          type        = 'error'
          heading     = 'Unsupported Action'
          message     = 'The requested action is not recognized by the system.'
          show_home   = abap_true
          status_code = 400 ).
      ENDIF.
    ELSEIF lv_method = 'GET'.
      IF lv_token IS NOT INITIAL.
        me->handle_token_action( server = server token = lv_token ).
      ELSE.
        me->handle_landing_page( server ).
      ENDIF.
    ELSE.
      me->render_message_page(
        server      = server
        title       = 'Method Not Allowed'
        type        = 'error'
        heading     = 'Method Not Allowed'
        message     = 'Only GET and POST requests are supported.'
        show_home   = abap_true
        status_code = 405 ).
    ENDIF.
  ENDMETHOD.


  METHOD handle_landing_page.
    DATA: lv_content     TYPE string,
          lv_client_text TYPE t000-mtext.

    SELECT SINGLE mtext FROM t000
      WHERE mandt = @sy-mandt
      INTO @lv_client_text.

    DATA(lv_client_raw) = COND string(
      WHEN lv_client_text IS NOT INITIAL THEN |{ sy-mandt } - { lv_client_text }|
      ELSE |{ sy-mandt }| ).
    DATA(lv_client_desc) = cl_http_utility=>escape_html( lv_client_raw ).

    lv_content =
      '<p class="desc">Enter your SAP username to receive a verification link.</p>' &&
      '<form id="ssprForm" method="POST" action="">' &&
      '  <input type="hidden" name="action" value="request_token" />' &&
      '  <div class="action-selector">' &&
      '    <label class="radio-card selected" id="opt_reset_pwd">' &&
      '      <input type="radio" name="action_type" value="RESET_PWD" checked onchange="updateActionUI(this.value)" />' &&
      '      <span>Reset Password</span>' &&
      '    </label>' &&
      '    <label class="radio-card" id="opt_unlock">' &&
      '      <input type="radio" name="action_type" value="UNLOCK" onchange="updateActionUI(this.value)" />' &&
      '      <span>Unlock Account</span>' &&
      '    </label>' &&
      '  </div>' &&
      '  <div class="form-group">' &&
      '    <label for="clientDisplay">SAP Client</label>' &&
      |    <input type="text" id="clientDisplay" value="{ lv_client_desc }" readonly style="background-color: #f8fafc; color: #475569; cursor: not-allowed; font-weight: 500;" />| &&
      '  </div>' &&
      '  <div class="form-group">' &&
      '    <label for="username">SAP User</label>' &&
      '    <input type="text" id="username" name="username" placeholder="" maxlength="12" required autofocus style="text-transform: uppercase;" />' &&
      '  </div>' &&
      '  <button type="submit" class="btn btn-primary" id="btnSubmit">' &&
      '    Send Reset Link' &&
      '  </button>' &&
      '</form>'.

    DATA(lv_html) = me->render_page(
      title      = 'SAP Self-Service'
      card_title = 'Account Self-Service'
      content    = lv_content ).

    me->render_response( server = server body = lv_html ).
  ENDMETHOD.


  METHOD handle_request_token.
    DATA: lv_username     TYPE bapibname-bapibname,
          lv_action_type  TYPE string,
          lv_user_email   TYPE string,
          lv_fullname     TYPE string,
          lv_user_found   TYPE abap_bool,
          lv_is_dialog    TYPE abap_bool,
          lv_is_locked    TYPE abap_bool,
          lv_admin_locked TYPE abap_bool,
          lv_is_expired   TYPE abap_bool,
          lv_client_ip    TYPE string,
          lv_token        TYPE string,
          lv_token_hash   TYPE zsspr_tokens-token,
          lv_base_url     TYPE string,
          lv_action_url   TYPE string,
          lv_mail_subj    TYPE string,
          lv_mail_body    TYPE string,
          ls_token_rec    TYPE zsspr_tokens.

    DATA(lv_raw_user) = to_upper( server->request->get_form_field( 'username' ) ).
    CONDENSE lv_raw_user NO-GAPS.

    lv_action_type = to_upper( server->request->get_form_field( 'action_type' ) ).
    IF lv_action_type <> 'UNLOCK'.
      lv_action_type = 'RESET_PWD'.
    ENDIF.

    lv_client_ip = me->get_client_ip( server ).

    " 1. Basic validation (username must be 1..12 alphanumeric/underscore/hyphen characters)
    IF lv_raw_user IS INITIAL.
      me->render_message_page(
        server      = server
        title       = 'Error'
        type        = 'warning'
        heading     = 'Missing Username'
        message     = 'Please enter your SAP username.'
        status_code = 400 ).
      RETURN.
    ENDIF.

    FIND PCRE '^[A-Z0-9_-]{1,12}$' IN lv_raw_user.
    IF sy-subrc <> 0.
      me->render_message_page(
        server      = server
        title       = 'Invalid Username'
        type        = 'warning'
        heading     = 'Invalid Username Format'
        message     = 'SAP username must be 1 to 12 letters, digits, underscores, or hyphens.'
        status_code = 400 ).
      RETURN.
    ENDIF.

    lv_username = lv_raw_user.

    " 2. Rate limiting: Check requests in the last 15 mins (handles midnight wrap-around)
    DATA: lv_recent_cnt TYPE i,
          lv_ip_cnt     TYPE i,
          lv_check_time TYPE tims,
          lv_prev_date  TYPE dats,
          lv_clean_date TYPE dats.

    lv_clean_date = sy-datum - 30.

    IF sy-uzeit >= '001500'.
      lv_check_time = sy-uzeit - 900.
      SELECT COUNT( * ) FROM zsspr_tokens
        WHERE bname        = @lv_username
          AND created_date = @sy-datum
          AND created_time >= @lv_check_time
        INTO @lv_recent_cnt.
    ELSE.
      lv_prev_date  = sy-datum - 1.
      lv_check_time = 86400 + sy-uzeit - 900.
      SELECT COUNT( * ) FROM zsspr_tokens
        WHERE bname = @lv_username
          AND ( created_date = @sy-datum
                OR ( created_date = @lv_prev_date AND created_time >= @lv_check_time ) )
        INTO @lv_recent_cnt.
    ENDIF.

    IF lv_recent_cnt >= 3.
      me->render_message_page(
        server      = server
        title       = 'Wait'
        type        = 'warning'
        heading     = 'Too Many Requests'
        message     = 'Please wait a few minutes before trying again.'
        status_code = 429 ).
      RETURN.
    ENDIF.

    " Per-IP limit (max 10 requests per 15 min across all users; no loopback exemption)
    IF lv_client_ip IS NOT INITIAL.
      IF sy-uzeit >= '001500'.
        SELECT COUNT( * ) FROM zsspr_tokens
          WHERE ip_address   = @lv_client_ip
            AND created_date = @sy-datum
            AND created_time >= @lv_check_time
          INTO @lv_ip_cnt.
      ELSE.
        SELECT COUNT( * ) FROM zsspr_tokens
          WHERE ip_address = @lv_client_ip
            AND ( created_date = @sy-datum
                  OR ( created_date = @lv_prev_date AND created_time >= @lv_check_time ) )
          INTO @lv_ip_cnt.
      ENDIF.

      IF lv_ip_cnt >= 10.
        me->render_message_page(
          server      = server
          title       = 'Wait'
          type        = 'warning'
          heading     = 'Too Many Requests'
          message     = 'Too many requests from your network. Please wait a few minutes before trying again.'
          status_code = 429 ).
        RETURN.
      ENDIF.
    ENDIF.

    " 3. Protection check: Never allow SSPR on critical system/admin accounts
    "    (Generic message avoids revealing which accounts belong to SUPER/ADMIN groups)
    IF me->is_protected_account( lv_username ) = abap_true.
      me->render_message_page(
        server    = server
        title     = 'Unavailable'
        type      = 'error'
        heading   = 'Self-Service Unavailable'
        message   = |Account { lv_username } is not eligible for self-service.|
        detail    = 'Please contact the IT Service Desk for assistance.'
        show_home = abap_true ).
      RETURN.
    ENDIF.

    " 4. Strict verification of User Master in SAP
    me->get_user_email_and_name(
      EXPORTING bname           = lv_username
      IMPORTING email           = lv_user_email
                fullname        = lv_fullname
                user_found      = lv_user_found
                is_dialog       = lv_is_dialog
                is_locked       = lv_is_locked
                is_admin_locked = lv_admin_locked
                is_expired      = lv_is_expired ).

    IF lv_user_found = abap_false.
      me->render_message_page(
        server    = server
        title     = 'Not Found'
        type      = 'error'
        heading   = 'User Not Found'
        message   = |SAP username { lv_username } does not exist.|
        detail    = 'Please check your username or contact the IT Service Desk.'
        show_home = abap_true ).
      RETURN.
    ENDIF.

    IF lv_is_dialog = abap_false OR lv_is_expired = abap_true.
      me->render_message_page(
        server    = server
        title     = 'Unavailable'
        type      = 'error'
        heading   = 'Self-Service Unavailable'
        message   = |Account { lv_username } is not eligible for self-service.|
        detail    = 'Only active dialog users within their validity period are permitted to use self-service. Please contact the IT Service Desk.'
        show_home = abap_true ).
      RETURN.
    ENDIF.

    " 5. Block accounts locked by an administrator (H1: only wrong-password locks allowed)
    IF lv_admin_locked = abap_true.
      me->render_message_page(
        server    = server
        title     = 'Account Locked by Administrator'
        type      = 'error'
        heading   = 'Administrator Lock Active'
        message   = |Account { lv_username } has been locked by an administrator and cannot be unlocked via self-service.|
        detail    = 'Please contact the IT Service Desk for authorization to reactivate your account.'
        show_home = abap_true ).
      RETURN.
    ENDIF.

    " 6. Strict check for UNLOCK: User must actually be locked due to failed logon attempts
    IF lv_action_type = 'UNLOCK' AND lv_is_locked = abap_false.
      me->render_message_page(
        server    = server
        title     = 'Account Active'
        type      = 'info'
        heading   = 'Account Not Locked'
        message   = |Account { lv_username } is active and not locked.|
        detail    = 'If you cannot sign in, please choose Reset Password.'
        show_home = abap_true ).
      RETURN.
    ENDIF.

    " 7. Check if user has email maintained
    CONDENSE lv_user_email NO-GAPS.
    IF lv_user_email IS INITIAL.
      me->render_message_page(
        server    = server
        title     = 'No Email'
        type      = 'error'
        heading   = 'No Email Configured'
        message   = |User { lv_username } does not have an email address configured in SAP.|
        detail    = 'Please contact the IT Service Desk to maintain your corporate email in transaction SU01.'
        show_home = abap_true ).
      RETURN.
    ENDIF.

    " 8. Generate 256-bit CSPRNG Token and store only its SHA-256 hash (H2 & H3)
    lv_token = me->generate_secure_token( ).
    lv_token_hash = me->hash_token( lv_token ).

    IF lv_token IS INITIAL OR lv_token_hash IS INITIAL.
      me->render_message_page(
        server    = server
        title     = 'Error'
        type      = 'error'
        heading   = 'Service Temporarily Unavailable'
        message   = 'Could not generate a cryptographic security token. Please try again later.'
        show_home = abap_true ).
      RETURN.
    ENDIF.

    " Housekeeping: purge tokens older than 30 days (committed together with the INSERT below)
    DELETE FROM zsspr_tokens WHERE created_date < @lv_clean_date.

    " Invalidate any previous PENDING tokens for the same user and action
    UPDATE zsspr_tokens
      SET status = 'EXPIRED'
      WHERE bname       = @lv_username
        AND action_type = @lv_action_type
        AND status      = 'PENDING'.

    CLEAR ls_token_rec.
    ls_token_rec-mandt        = sy-mandt.
    ls_token_rec-token        = lv_token_hash.
    ls_token_rec-bname        = lv_username.
    ls_token_rec-email        = lv_user_email.
    ls_token_rec-action_type  = lv_action_type.
    ls_token_rec-status       = 'PENDING'.
    ls_token_rec-created_date = sy-datum.
    ls_token_rec-created_time = sy-uzeit.

    " Expiration: 15 minutes (900 seconds)
    DATA: lv_exp_seconds TYPE i,
          lv_exp_time    TYPE tims,
          lv_exp_date    TYPE dats.

    lv_exp_date    = sy-datum.
    lv_exp_seconds = sy-uzeit + 900.
    IF lv_exp_seconds >= 86400.
      lv_exp_date = lv_exp_date + 1.
      lv_exp_time = lv_exp_seconds - 86400.
    ELSE.
      lv_exp_time = lv_exp_seconds.
    ENDIF.

    ls_token_rec-expires_date = lv_exp_date.
    ls_token_rec-expires_time = lv_exp_time.
    ls_token_rec-ip_address   = lv_client_ip.
    ls_token_rec-attempts     = 0.

    INSERT zsspr_tokens FROM @ls_token_rec.
    COMMIT WORK AND WAIT.

    " 9. Send Email with Verification Link (contains raw token; DB holds only SHA-256 hash)
    lv_base_url   = me->get_base_url( server ).
    lv_action_url = lv_base_url && '?token=' && lv_token.

    DATA(lv_esc_fullname) = cl_http_utility=>escape_html( lv_fullname ).
    DATA(lv_esc_username) = cl_http_utility=>escape_html( CONV string( lv_username ) ).
    DATA(lv_esc_act_url)  = cl_http_utility=>escape_html( lv_action_url ).

    IF lv_action_type = 'UNLOCK'.
      lv_mail_subj = |[SAP Security] Account Unlock Request ({ lv_username })|.
      lv_mail_body =
        '<html><head><meta charset="utf-8"/></head><body style="font-family: -apple-system, BlinkMacSystemFont, Arial, sans-serif; color: #1e293b; line-height: 1.6;">' &&
        '<div style="max-width: 520px; margin: 20px auto; border: 1px solid #e2e8f0; border-radius: 8px; padding: 24px; background: #ffffff;">' &&
        '  <h2 style="color: #0f172a; margin-top: 0; font-size: 16px;">SAP Account Unlock Request</h2>' &&
        |  <p>Hello <strong>{ lv_esc_fullname }</strong> ({ lv_esc_username }),</p>| &&
        '  <p>A request to unlock your SAP account was received. Click below to review and confirm:</p>' &&
        '  <div style="text-align: center; margin: 24px 0;">' &&
        '    <a href="' && lv_esc_act_url && '" style="background: #0f172a; color: #ffffff; padding: 10px 24px; text-decoration: none; border-radius: 6px; font-weight: 600; display: inline-block;">Unlock Account</a>' &&
        '  </div>' &&
        '  <p style="font-size: 12px; color: #64748b;">This link expires in 15 minutes. If you did not make this request, you can ignore this email.</p>' &&
        '</div></body></html>'.
    ELSE.
      lv_mail_subj = |[SAP Security] Password Reset Request ({ lv_username })|.
      lv_mail_body =
        '<html><head><meta charset="utf-8"/></head><body style="font-family: -apple-system, BlinkMacSystemFont, Arial, sans-serif; color: #1e293b; line-height: 1.6;">' &&
        '<div style="max-width: 520px; margin: 20px auto; border: 1px solid #e2e8f0; border-radius: 8px; padding: 24px; background: #ffffff;">' &&
        '  <h2 style="color: #0f172a; margin-top: 0; font-size: 16px;">SAP Password Reset Request</h2>' &&
        |  <p>Hello <strong>{ lv_esc_fullname }</strong> ({ lv_esc_username }),</p>| &&
        '  <p>A request to reset your SAP password was received. Click below to continue:</p>' &&
        '  <div style="text-align: center; margin: 24px 0;">' &&
        '    <a href="' && lv_esc_act_url && '" style="background: #0f172a; color: #ffffff; padding: 10px 24px; text-decoration: none; border-radius: 6px; font-weight: 600; display: inline-block;">Reset Password</a>' &&
        '  </div>' &&
        '  <p style="font-size: 12px; color: #64748b;">This link expires in 15 minutes. If you did not make this request, you can ignore this email.</p>' &&
        '</div></body></html>'.
    ENDIF.

    DATA(lv_sent_ok) = me->send_notification_email(
      recipient_email = lv_user_email
      subject         = lv_mail_subj
      html_content    = lv_mail_body ).

    IF lv_sent_ok = abap_false.
      UPDATE zsspr_tokens
        SET status = 'INVALID'
        WHERE token = @lv_token_hash.
      COMMIT WORK.
      me->render_message_page(
        server      = server
        title       = 'Delivery Error'
        type        = 'error'
        heading     = 'Email Delivery Failed'
        message     = 'The verification email could not be sent right now. Please try again later or contact the IT Service Desk.'
        show_home   = abap_true
        status_code = 500 ).
      RETURN.
    ENDIF.

    DATA(lv_masked) = me->mask_email( lv_user_email ).

    me->render_message_page(
      server    = server
      title     = 'Check Email'
      type      = 'success'
      heading   = 'Verification Link Sent'
      message   = |A verification link was sent to your registered corporate email ({ lv_masked }).|
      detail    = 'Please check your inbox (and spam folder). The security link expires in 15 minutes.'
      show_home = abap_true ).
  ENDMETHOD.


  METHOD validate_and_load_token.
    DATA: lv_user_email   TYPE string,
          lv_fullname     TYPE string,
          lv_user_found   TYPE abap_bool,
          lv_is_dialog    TYPE abap_bool,
          lv_is_locked    TYPE abap_bool,
          lv_admin_locked TYPE abap_bool,
          lv_user_expired TYPE abap_bool,
          lv_tok_clean    TYPE string.

    CLEAR: token_hash, token_rec, is_valid.

    lv_tok_clean = raw_token.
    CONDENSE lv_tok_clean NO-GAPS.

    " 1. Validate format (64 hex characters) and hash with SHA-256
    FIND PCRE '^[A-Fa-f0-9]{64}$' IN lv_tok_clean.
    IF sy-subrc <> 0.
      me->render_message_page(
        server  = server
        title   = 'Invalid Link'
        type    = 'error'
        heading = 'Invalid Link'
        message = 'The security link could not be found or is invalid. Please submit a new request.' ).
      RETURN.
    ENDIF.

    token_hash = me->hash_token( to_upper( lv_tok_clean ) ).
    IF token_hash IS INITIAL.
      me->render_message_page(
        server  = server
        title   = 'Invalid Link'
        type    = 'error'
        heading = 'Invalid Link'
        message = 'The security link could not be validated. Please submit a new request.' ).
      RETURN.
    ENDIF.

    " 2. Lookup hashed token in database (DB stores SHA-256 hash only; pre-upgrade plaintext tokens are intentionally not accepted)
    SELECT SINGLE * FROM zsspr_tokens
      WHERE token = @token_hash
      INTO @token_rec.

    IF sy-subrc <> 0.
      me->render_message_page(
        server  = server
        title   = 'Invalid Link'
        type    = 'error'
        heading = 'Invalid Link'
        message = 'The security link could not be found or is invalid. Please submit a new request.' ).
      RETURN.
    ENDIF.

    " 3. Check token status
    IF token_rec-status = 'USED'.
      me->render_message_page(
        server  = server
        title   = 'Already Used'
        type    = 'warning'
        heading = 'Link Already Used'
        message = 'This link has already been used. Please submit a new request.' ).
      RETURN.
    ELSEIF token_rec-status <> 'PENDING'.
      me->render_message_page(
        server  = server
        title   = 'Unavailable'
        type    = 'error'
        heading = 'Link Expired or Invalid'
        message = 'This link is no longer valid. Please submit a new request.' ).
      RETURN.
    ENDIF.

    " 4. Check expected action type if specified
    IF expected_action IS NOT INITIAL AND token_rec-action_type <> expected_action.
      me->render_message_page(
        server  = server
        title   = 'Invalid Request'
        type    = 'error'
        heading = 'Invalid Action'
        message = 'This security link is not valid for the requested action.' ).
      RETURN.
    ENDIF.

    " 5. Check attempts limit
    IF token_rec-attempts >= 5.
      UPDATE zsspr_tokens SET status = 'EXPIRED' WHERE token = @token_hash.
      COMMIT WORK.
      me->render_message_page(
        server  = server
        title   = 'Link Locked'
        type    = 'error'
        heading = 'Too Many Failed Attempts'
        message = 'This security link has been locked due to too many failed attempts. Please submit a new request.' ).
      RETURN.
    ENDIF.

    " 6. Check token expiration (C1: enforced identically on both GET and POST)
    DATA(lv_is_expired) = abap_false.
    IF token_rec-expires_date < sy-datum.
      lv_is_expired = abap_true.
    ELSEIF token_rec-expires_date = sy-datum AND token_rec-expires_time < sy-uzeit.
      lv_is_expired = abap_true.
    ENDIF.

    IF lv_is_expired = abap_true.
      UPDATE zsspr_tokens SET status = 'EXPIRED' WHERE token = @token_hash.
      COMMIT WORK.
      me->render_message_page(
        server  = server
        title   = 'Expired'
        type    = 'warning'
        heading = 'Link Expired'
        message = 'This security link has expired (15-minute limit). Please submit a new request.' ).
      RETURN.
    ENDIF.

    " 7. Defence-in-Depth: Verify account is not protected and still eligible
    IF me->is_protected_account( token_rec-bname ) = abap_true.
      UPDATE zsspr_tokens SET status = 'INVALID' WHERE token = @token_hash.
      COMMIT WORK.
      me->render_message_page(
        server  = server
        title   = 'Unavailable'
        type    = 'error'
        heading   = 'Self-Service Unavailable'
        message = 'This account is not eligible for self-service. Please contact the IT Service Desk.' ).
      RETURN.
    ENDIF.

    me->get_user_email_and_name(
      EXPORTING bname           = token_rec-bname
      IMPORTING email           = lv_user_email
                fullname        = lv_fullname
                user_found      = lv_user_found
                is_dialog       = lv_is_dialog
                is_locked       = lv_is_locked
                is_admin_locked = lv_admin_locked
                is_expired      = lv_user_expired ).

    IF lv_user_found = abap_false OR lv_is_dialog = abap_false OR lv_user_expired = abap_true.
      UPDATE zsspr_tokens SET status = 'INVALID' WHERE token = @token_hash.
      COMMIT WORK.
      me->render_message_page(
        server  = server
        title   = 'Unavailable'
        type    = 'error'
        heading = 'Self-Service Unavailable'
        message = 'This account is no longer eligible for self-service. Please contact the IT Service Desk.' ).
      RETURN.
    ENDIF.

    IF lv_admin_locked = abap_true.
      UPDATE zsspr_tokens SET status = 'INVALID' WHERE token = @token_hash.
      COMMIT WORK.
      me->render_message_page(
        server  = server
        title   = 'Administrator Lock Active'
        type    = 'error'
        heading = 'Administrator Lock Active'
        message = 'This account has been locked by an administrator and cannot be unlocked via self-service. Please contact the IT Service Desk.' ).
      RETURN.
    ENDIF.

    is_valid = abap_true.
  ENDMETHOD.


  METHOD handle_token_action.
    DATA: lv_token_hash TYPE zsspr_tokens-token,
          ls_token      TYPE zsspr_tokens,
          lv_valid      TYPE abap_bool.

    me->validate_and_load_token(
      EXPORTING server     = server
                raw_token  = token
      IMPORTING token_hash = lv_token_hash
                token_rec  = ls_token
                is_valid   = lv_valid ).

    IF lv_valid = abap_false.
      RETURN.
    ENDIF.

    " M3: Never mutate state on GET (prevents mail scanners / Safe Links from consuming token)
    IF ls_token-action_type = 'UNLOCK'.
      me->render_unlock_form(
        server = server
        token  = token
        bname  = ls_token-bname ).
    ELSE.
      me->render_password_form(
        server = server
        token  = token
        bname  = ls_token-bname ).
    ENDIF.
  ENDMETHOD.


  METHOD handle_confirm_unlock.
    DATA: lv_token      TYPE string,
          lv_token_hash TYPE zsspr_tokens-token,
          ls_token      TYPE zsspr_tokens,
          lv_valid      TYPE abap_bool,
          lt_return     TYPE STANDARD TABLE OF bapiret2.

    lv_token = server->request->get_form_field( 'token' ).

    me->validate_and_load_token(
      EXPORTING server          = server
                raw_token       = lv_token
                expected_action = 'UNLOCK'
      IMPORTING token_hash      = lv_token_hash
                token_rec       = ls_token
                is_valid        = lv_valid ).

    IF lv_valid = abap_false.
      RETURN.
    ENDIF.

    " Re-verify USR02 lock bitmask right before unlock (prevents TOCTOU admin-lock bypass)
    DATA: lv_cur_uflag TYPE usr02-uflag.
    SELECT SINGLE uflag FROM usr02
      WHERE bname = @ls_token-bname
      INTO @lv_cur_uflag.
    IF sy-subrc <> 0 OR ( lv_cur_uflag MOD 128 ) >= 32.
      UPDATE zsspr_tokens SET status = 'INVALID' WHERE token = @lv_token_hash.
      COMMIT WORK.
      me->render_message_page(
        server      = server
        title       = 'Administrator Lock Active'
        type        = 'error'
        heading     = 'Administrator Lock Active'
        message     = 'This account has been locked by an administrator and cannot be unlocked via self-service. Please contact the IT Service Desk.'
        status_code = 403 ).
      RETURN.
    ENDIF.

    " M4: Atomically claim the token before executing BAPI
    UPDATE zsspr_tokens
      SET status    = 'USED',
          used_date = @sy-datum,
          used_time = @sy-uzeit
      WHERE token  = @lv_token_hash
        AND status = 'PENDING'.

    IF sy-dbcnt <> 1.
      me->render_message_page(
        server  = server
        title   = 'Already Used'
        type    = 'warning'
        heading = 'Link Already Used'
        message = 'This security link has already been processed. Please submit a new request.' ).
      RETURN.
    ENDIF.
    COMMIT WORK AND WAIT.

    CALL FUNCTION 'BAPI_USER_UNLOCK'
      EXPORTING
        username = ls_token-bname
      TABLES
        return   = lt_return.

    DATA(lv_has_err) = abap_false.
    LOOP AT lt_return INTO DATA(ls_ret).
      IF ls_ret-type = 'E' OR ls_ret-type = 'A'.
        lv_has_err = abap_true.
      ENDIF.
    ENDLOOP.

    IF lv_has_err = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      me->render_message_page(
        server  = server
        title   = 'Error'
        type    = 'error'
        heading = 'Unlock Failed'
        message = 'The account could not be unlocked at this time. Please contact the IT Service Desk.' ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = 'X'.

    " Send notification email
    DATA(lv_esc_bname) = cl_http_utility=>escape_html( CONV string( ls_token-bname ) ).
    DATA(lv_mail_body) =
      '<html><body style="font-family: -apple-system, BlinkMacSystemFont, Arial, sans-serif; color: #1e293b;">' &&
      '<div style="max-width: 520px; margin: 20px auto; border: 1px solid #e2e8f0; border-radius: 8px; padding: 24px; background: #ffffff;">' &&
      '  <h2 style="color: #16a34a; margin-top: 0; font-size: 16px;">SAP Account Unlocked</h2>' &&
      |  <p>Your SAP account <strong>{ lv_esc_bname }</strong> has been successfully unlocked.</p>| &&
      '  <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 16px 0;"/>' &&
      '  <p style="font-size: 12px; color: #64748b;">If you did not make this request, please contact your IT administrator.</p>' &&
      '</div></body></html>'.

    me->send_notification_email(
      recipient_email = ls_token-email
      subject         = |[SAP Security] Account { ls_token-bname } unlocked|
      html_content    = lv_mail_body ).

    me->render_message_page(
      server    = server
      title     = 'Account Unlocked'
      type      = 'success'
      heading   = 'Account Unlocked'
      message   = |Your SAP user account { ls_token-bname } has been unlocked.|
      show_home = abap_true ).
  ENDMETHOD.


  METHOD handle_set_password.
    DATA: lv_token       TYPE string,
          lv_token_hash  TYPE zsspr_tokens-token,
          lv_new_pwd     TYPE string,
          lv_confirm_pwd TYPE string,
          ls_token       TYPE zsspr_tokens,
          lv_valid       TYPE abap_bool.

    lv_token       = server->request->get_form_field( 'token' ).
    lv_new_pwd     = server->request->get_form_field( 'new_password' ).
    lv_confirm_pwd = server->request->get_form_field( 'confirm_password' ).

    " 1. Full token validation (C1: enforces expiration, status, attempts, protected & admin-lock checks)
    me->validate_and_load_token(
      EXPORTING server          = server
                raw_token       = lv_token
                expected_action = 'RESET_PWD'
      IMPORTING token_hash      = lv_token_hash
                token_rec       = ls_token
                is_valid        = lv_valid ).

    IF lv_valid = abap_false.
      RETURN.
    ENDIF.

    " 2. Verify passwords match
    IF lv_new_pwd IS INITIAL OR lv_new_pwd <> lv_confirm_pwd.
      DATA(lv_att_1) = me->increment_token_attempts( lv_token_hash ).
      IF lv_att_1 >= 5.
        UPDATE zsspr_tokens SET status = 'EXPIRED' WHERE token = @lv_token_hash.
        COMMIT WORK.
        me->render_message_page(
          server      = server
          title       = 'Link Locked'
          type        = 'error'
          heading     = 'Too Many Failed Attempts'
          message     = 'This reset link has been locked due to too many failed attempts. Please request a new one.'
          status_code = 429 ).
        RETURN.
      ENDIF.
      me->render_password_form(
        server  = server
        token   = lv_token
        bname   = ls_token-bname
        err_msg = 'Passwords do not match.' ).
      RETURN.
    ENDIF.

    " 3. Password policy checks (10..40 chars, uppercase, lowercase, number, special char)
    DATA: lv_pwd_ok TYPE abap_bool VALUE abap_true.

    IF strlen( lv_new_pwd ) < 10 OR strlen( lv_new_pwd ) > 40.
      lv_pwd_ok = abap_false.
    ENDIF.

    IF NOT contains_any_of( val = lv_new_pwd sub = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' ).
      lv_pwd_ok = abap_false.
    ENDIF.

    IF NOT contains_any_of( val = lv_new_pwd sub = 'abcdefghijklmnopqrstuvwxyz' ).
      lv_pwd_ok = abap_false.
    ENDIF.

    IF NOT contains_any_of( val = lv_new_pwd sub = '0123456789' ).
      lv_pwd_ok = abap_false.
    ENDIF.

    IF NOT contains_any_not_of( val = lv_new_pwd sub = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' ).
      lv_pwd_ok = abap_false.
    ENDIF.

    IF lv_pwd_ok = abap_false.
      DATA(lv_att_2) = me->increment_token_attempts( lv_token_hash ).
      IF lv_att_2 >= 5.
        UPDATE zsspr_tokens SET status = 'EXPIRED' WHERE token = @lv_token_hash.
        COMMIT WORK.
        me->render_message_page(
          server      = server
          title       = 'Link Locked'
          type        = 'error'
          heading     = 'Too Many Failed Attempts'
          message     = 'This reset link has been locked due to too many failed attempts. Please request a new one.'
          status_code = 429 ).
        RETURN.
      ENDIF.
      me->render_password_form(
        server  = server
        token   = lv_token
        bname   = ls_token-bname
        err_msg = 'Password must be 10 to 40 characters and include uppercase, lowercase, numbers, and special characters.' ).
      RETURN.
    ENDIF.

    " 4. M4: Atomically claim token before calling BAPI
    UPDATE zsspr_tokens
      SET status    = 'USED',
          used_date = @sy-datum,
          used_time = @sy-uzeit
      WHERE token  = @lv_token_hash
        AND status = 'PENDING'.

    IF sy-dbcnt <> 1.
      me->render_message_page(
        server  = server
        title   = 'Already Used'
        type    = 'warning'
        heading = 'Link Already Used'
        message = 'This reset link has already been processed. Please submit a new request.' ).
      RETURN.
    ENDIF.
    COMMIT WORK AND WAIT.

    " 5. Update password via standard BAPI_USER_CHANGE FIRST (H4: never unlock before password succeeds)
    DATA: ls_pwd        TYPE bapipwd,
          ls_pwdx       TYPE bapipwdx,
          lt_return     TYPE STANDARD TABLE OF bapiret2,
          lt_unlock_ret TYPE STANDARD TABLE OF bapiret2,
          lv_errmsg     TYPE string,
          lv_one_msg    TYPE string.

    ls_pwd-bapipwd  = lv_new_pwd.
    ls_pwdx-bapipwd = 'X'.

    CALL FUNCTION 'BAPI_USER_CHANGE'
      EXPORTING
        username       = ls_token-bname
        password       = ls_pwd
        passwordx      = ls_pwdx
        productive_pwd = 'X'
      TABLES
        return         = lt_return.

    DATA(lv_has_err) = abap_false.
    LOOP AT lt_return INTO DATA(ls_ret).
      IF ls_ret-type = 'E' OR ls_ret-type = 'A'.
        lv_has_err = abap_true.
        lv_one_msg = ls_ret-message.
        IF lv_one_msg IS INITIAL AND ls_ret-id IS NOT INITIAL.
          MESSAGE ID ls_ret-id TYPE ls_ret-type NUMBER ls_ret-number
            WITH ls_ret-message_v1 ls_ret-message_v2 ls_ret-message_v3 ls_ret-message_v4
            INTO lv_one_msg.
        ENDIF.
        IF lv_one_msg IS NOT INITIAL.
          IF lv_errmsg IS INITIAL.
            lv_errmsg = lv_one_msg.
          ELSE.
            lv_errmsg = lv_errmsg && ' | ' && lv_one_msg.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF lv_has_err = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      DATA(lv_att_3) = me->increment_token_attempts( lv_token_hash ).
      DATA(lv_now_expired) = abap_false.
      IF ls_token-expires_date < sy-datum
         OR ( ls_token-expires_date = sy-datum AND ls_token-expires_time < sy-uzeit ).
        lv_now_expired = abap_true.
      ENDIF.

      IF lv_att_3 >= 5 OR lv_now_expired = abap_true.
        UPDATE zsspr_tokens
          SET status = 'EXPIRED'
          WHERE token = @lv_token_hash.
        COMMIT WORK.
        me->render_message_page(
          server      = server
          title       = 'Link Expired'
          type        = 'error'
          heading     = COND #( WHEN lv_att_3 >= 5 THEN 'Too Many Failed Attempts' ELSE 'Link Expired' )
          message     = 'This reset link is no longer valid. Please request a new one.'
          status_code = COND #( WHEN lv_att_3 >= 5 THEN 429 ELSE 400 ) ).
        RETURN.
      ELSE.
        UPDATE zsspr_tokens
          SET status    = 'PENDING',
              used_date = '00000000',
              used_time = '000000'
          WHERE token = @lv_token_hash.
        COMMIT WORK.
        IF lv_errmsg IS INITIAL.
          lv_errmsg = 'Password did not meet SAP system policy requirements.'.
        ENDIF.
        me->render_password_form(
          server  = server
          token   = lv_token
          bname   = ls_token-bname
          err_msg = |SAP password policy: { lv_errmsg }| ).
        RETURN.
      ENDIF.
    ENDIF.

    " 6. H4: Only unlock account AFTER password change succeeded AND only for wrong-logon locks (not admin locks)
    DATA: lv_uflag_now TYPE usr02-uflag.
    SELECT SINGLE uflag FROM usr02
      WHERE bname = @ls_token-bname
      INTO @lv_uflag_now.

    IF sy-subrc = 0 AND lv_uflag_now >= 128 AND ( lv_uflag_now MOD 128 ) < 32.
      CALL FUNCTION 'BAPI_USER_UNLOCK'
        EXPORTING
          username = ls_token-bname
        TABLES
          return   = lt_unlock_ret.
    ENDIF.

    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = 'X'.

    " 7. C2: Check system SID
    " - If SID contains 'P' (Production): strictly prohibit direct UPDATE on USR02 (AGENTS.md §1).
    "   Keep initial password state set by BAPI_USER_CHANGE and inform user to change password at first logon.
    " - If Non-Production (Dev/Test, SID without 'P'): set productive password for testing convenience.
    DATA(lv_is_prod) = me->is_production_system( ).

    IF lv_is_prod = abap_false.
      DATA: lv_pwd_time    TYPE tims,
            lt_clear_users TYPE STANDARD TABLE OF ususers,
            lt_suid_bname  TYPE suid_tt_bname.

      lv_pwd_time = sy-uzeit.
      IF lv_pwd_time IS INITIAL.
        lv_pwd_time = '000001'.
      ENDIF.

      UPDATE usr02
        SET pwdinitial = 2,
            pwdstate   = 0,
            ltime      = @lv_pwd_time,
            pwdchgdate = @sy-datum,
            bcda1      = '00000000'
        WHERE bname = @ls_token-bname.

      APPEND VALUE #( bname = ls_token-bname ) TO lt_clear_users.
      APPEND VALUE #( bname = ls_token-bname ) TO lt_suid_bname.

      CALL FUNCTION 'SUSR_USER_BUFFERS_CLEAR'
        TABLES
          users  = lt_clear_users
        EXCEPTIONS
          OTHERS = 0.

      TRY.
          cl_identity_factory=>cleanup( it_bname = lt_suid_bname ).
        CATCH cx_suid_identity.
      ENDTRY.

      COMMIT WORK AND WAIT.
    ENDIF.

    " 8. Send security confirmation email
    DATA(lv_esc_bname) = cl_http_utility=>escape_html( CONV string( ls_token-bname ) ).
    DATA: lv_prod_mail_note TYPE string,
          lv_detail_msg     TYPE string.

    IF lv_is_prod = abap_true.
      lv_prod_mail_note =
        '  <p style="background: #fffbeb; border: 1px solid #fde68a; color: #92400e; padding: 10px 12px; border-radius: 6px; font-size: 13px;">' &&
        '    <strong>Note:</strong> Upon your first logon to SAP, you will be prompted to change this password one more time to activate your permanent password.' &&
        '  </p>'.
      lv_detail_msg =
        'Please note: At your first logon to SAP, the system will prompt you to change your password one more time. If your account was locked due to failed logon attempts, it has also been unlocked.'.
    ELSE.
      lv_prod_mail_note = ''.
      lv_detail_msg     = 'If your account was locked, it has also been automatically unlocked.'.
    ENDIF.

    DATA(lv_mail_body) =
      '<html><body style="font-family: -apple-system, BlinkMacSystemFont, Arial, sans-serif; color: #1e293b;">' &&
      '<div style="max-width: 520px; margin: 20px auto; border: 1px solid #e2e8f0; border-radius: 8px; padding: 24px; background: #ffffff;">' &&
      '  <h2 style="color: #16a34a; margin-top: 0; font-size: 16px;">SAP Password Updated</h2>' &&
      |  <p>The password for SAP account <strong>{ lv_esc_bname }</strong> was successfully updated.</p>| &&
      lv_prod_mail_note &&
      '  <p>If your account was locked due to failed logon attempts, it has also been automatically unlocked.</p>' &&
      '  <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 16px 0;"/>' &&
      '  <p style="font-size: 12px; color: #64748b;">If you did not make this change, please contact your IT administrator.</p>' &&
      '</div></body></html>'.

    me->send_notification_email(
      recipient_email = ls_token-email
      subject         = |[SAP Security] Password updated for { ls_token-bname }|
      html_content    = lv_mail_body ).

    me->render_message_page(
      server    = server
      title     = 'Password Updated'
      type      = 'success'
      heading   = 'Password Updated'
      message   = |The password for { ls_token-bname } has been updated.|
      detail    = lv_detail_msg
      show_home = abap_true ).
  ENDMETHOD.


  METHOD render_unlock_form.
    DATA: lv_content   TYPE string,
          lv_esc_bname TYPE string,
          lv_esc_token TYPE string.

    lv_esc_bname = cl_http_utility=>escape_html( CONV string( bname ) ).
    lv_esc_token = cl_http_utility=>escape_html( token ).

    lv_content =
      |<p class="desc">Account: <strong>{ lv_esc_bname }</strong> &bull; Client: <strong>{ sy-mandt }</strong></p>| &&
      '<p class="desc">Click the button below to confirm unlocking your SAP account.</p>' &&
      '<form id="unlockForm" method="POST" action="">' &&
      '  <input type="hidden" name="action" value="confirm_unlock" />' &&
      '  <input type="hidden" name="token" value="' && lv_esc_token && '" />' &&
      '  <button type="submit" class="btn btn-primary">' &&
      '    Confirm Account Unlock' &&
      '  </button>' &&
      '</form>'.

    DATA(lv_html) = me->render_page(
      title      = 'Unlock Account'
      card_title = 'Confirm Account Unlock'
      content    = lv_content ).

    me->render_response( server = server body = lv_html ).
  ENDMETHOD.


  METHOD render_password_form.
    DATA: lv_content    TYPE string,
          lv_esc_bname  TYPE string,
          lv_esc_token  TYPE string,
          lv_esc_errmsg TYPE string.

    lv_esc_bname = cl_http_utility=>escape_html( CONV string( bname ) ).
    lv_esc_token = cl_http_utility=>escape_html( token ).

    lv_content =
      |<p class="desc">Account: <strong>{ lv_esc_bname }</strong> &bull; Client: <strong>{ sy-mandt }</strong></p>|.

    IF err_msg IS NOT INITIAL.
      lv_esc_errmsg = cl_http_utility=>escape_html( err_msg ).
      lv_content = lv_content &&
        '<div class="alert alert-error">' && lv_esc_errmsg && '</div>'.
    ENDIF.

    lv_content = lv_content &&
      '<form id="pwdForm" method="POST" action="" onsubmit="return validatePwdForm()">' &&
      '  <input type="hidden" name="action" value="set_password" />' &&
      '  <input type="hidden" name="token" value="' && lv_esc_token && '" />' &&
      '  <div class="form-group">' &&
      '    <label for="new_password">New Password</label>' &&
      '    <input type="password" id="new_password" name="new_password" required autofocus oninput="checkStrength(this.value)" />' &&
      '  </div>' &&
      '  <div class="form-group">' &&
      '    <label for="confirm_password">Confirm Password</label>' &&
      '    <input type="password" id="confirm_password" name="confirm_password" required oninput="checkMatch()" />' &&
      '    <small id="matchMsg" class="hint"></small>' &&
      '  </div>' &&
      '  <ul class="rules-list">' &&
      '    <li id="r_len">&bull; At least 10 characters</li>' &&
      '    <li id="r_upper">&bull; At least 1 uppercase letter (A-Z)</li>' &&
      '    <li id="r_lower">&bull; At least 1 lowercase letter (a-z)</li>' &&
      '    <li id="r_num">&bull; At least 1 number (0-9)</li>' &&
      '    <li id="r_spec">&bull; At least 1 special character</li>' &&
      '  </ul>' &&
      '  <button type="submit" class="btn btn-primary" id="btnSubmitPwd">' &&
      '    Update Password' &&
      '  </button>' &&
      '</form>'.

    DATA(lv_html) = me->render_page(
      title      = 'Set Password'
      card_title = 'Set New Password'
      content    = lv_content ).

    me->render_response( server = server body = lv_html ).
  ENDMETHOD.


  METHOD render_message_page.
    DATA: lv_icon_html   TYPE string,
          lv_color_cls   TYPE string,
          lv_content     TYPE string,
          lv_esc_heading TYPE string,
          lv_esc_message TYPE string,
          lv_esc_detail  TYPE string,
          lv_esc_url     TYPE string,
          lv_home_path   TYPE string.

    lv_esc_heading = cl_http_utility=>escape_html( heading ).
    lv_esc_message = cl_http_utility=>escape_html( message ).

    CASE type.
      WHEN 'success'.
        lv_color_cls = 'msg-success'.
        lv_icon_html = '<div class="msg-icon text-success">&#10003;</div>'.
      WHEN 'warning'.
        lv_color_cls = 'msg-warning'.
        lv_icon_html = '<div class="msg-icon text-warning">&#9888;</div>'.
      WHEN 'error'.
        lv_color_cls = 'msg-error'.
        lv_icon_html = '<div class="msg-icon text-error">&#10007;</div>'.
      WHEN OTHERS.
        lv_color_cls = 'msg-info'.
        lv_icon_html = '<div class="msg-icon text-info">&#8505;</div>'.
    ENDCASE.

    lv_content =
      '<div class="msg-box ' && lv_color_cls && '">' &&
      lv_icon_html &&
      '  <h2 class="msg-heading">' && lv_esc_heading && '</h2>' &&
      '  <p class="msg-text">' && lv_esc_message && '</p>'.

    IF detail IS NOT INITIAL.
      lv_esc_detail = cl_http_utility=>escape_html( detail ).
      lv_content = lv_content &&
        '<div class="msg-detail">' && lv_esc_detail && '</div>'.
    ENDIF.

    IF show_home = abap_true.
      lv_home_path = server->request->get_header_field( '~script_name' ).
      IF lv_home_path IS INITIAL.
        lv_home_path = server->request->get_header_field( '~path' ).
      ENDIF.
      FIND PCRE '^/[A-Za-z0-9_/-]+$' IN lv_home_path.
      IF sy-subrc <> 0.
        lv_home_path = '/reset'.
      ENDIF.
      lv_esc_url = cl_http_utility=>escape_html( lv_home_path ).
      lv_content = lv_content &&
        '<div style="margin-top: 24px;">' &&
        '  <a href="' && lv_esc_url && '" class="btn btn-secondary">Back to Portal</a>' &&
        '</div>'.
    ENDIF.

    lv_content = lv_content && '</div>'.

    DATA(lv_html) = me->render_page(
      title      = title
      card_title = heading
      content    = lv_content ).

    me->render_response(
      server      = server
      status_code = status_code
      body        = lv_html ).
  ENDMETHOD.


  METHOD render_page.
    DATA: lv_sub_html   TYPE string,
          lv_esc_title  TYPE string,
          lv_esc_card_t TYPE string,
          lv_esc_card_s TYPE string.

    lv_esc_title  = cl_http_utility=>escape_html( title ).
    lv_esc_card_t = cl_http_utility=>escape_html( card_title ).

    IF card_sub IS NOT INITIAL.
      lv_esc_card_s = cl_http_utility=>escape_html( card_sub ).
      lv_sub_html   = '<p>' && lv_esc_card_s && '</p>'.
    ENDIF.

    html =
      '<!DOCTYPE html>' &&
      '<html lang="en">' &&
      '<head>' &&
      '  <meta charset="utf-8"/>' &&
      '  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>' &&
      '  <title>' && lv_esc_title && '</title>' &&
      '  <style>' &&
      '    :root {' &&
      '      --text-main: #0f172a;' &&
      '      --text-muted: #64748b;' &&
      '      --border: #e2e8f0;' &&
      '      --bg: #f8fafc;' &&
      '      --card-bg: #ffffff;' &&
      '      --primary: #0f172a;' &&
      '      --primary-hover: #1e293b;' &&
      '      --success: #16a34a;' &&
      '      --error: #dc2626;' &&
      '      --warning: #d97706;' &&
      '    }' &&
      '    * { box-sizing: border-box; margin: 0; padding: 0; }' &&
      '    body {' &&
      '      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;' &&
      '      background-color: var(--bg);' &&
      '      color: var(--text-main);' &&
      '      min-height: 100vh;' &&
      '      display: flex;' &&
      '      align-items: center;' &&
      '      justify-content: center;' &&
      '      padding: 24px;' &&
      '    }' &&
      '    .card {' &&
      '      background: var(--card-bg);' &&
      '      width: 100%;' &&
      '      max-width: 440px;' &&
      '      border: 1px solid var(--border);' &&
      '      border-radius: 12px;' &&
      '      box-shadow: 0 4px 6px -1px rgba(0,0,0,0.05), 0 2px 4px -2px rgba(0,0,0,0.05);' &&
      '      padding: 32px;' &&
      '    }' &&
      '    .card-header {' &&
      '      margin-bottom: 24px;' &&
      '      text-align: center;' &&
      '    }' &&
      '    .card-header h1 {' &&
      '      font-size: 20px;' &&
      '      font-weight: 600;' &&
      '      letter-spacing: -0.02em;' &&
      '      color: var(--text-main);' &&
      '      margin-bottom: 4px;' &&
      '    }' &&
      '    .card-header p {' &&
      '      font-size: 13px;' &&
      '      color: var(--text-muted);' &&
      '    }' &&
      '    .desc {' &&
      '      color: var(--text-muted);' &&
      '      font-size: 14px;' &&
      '      line-height: 1.5;' &&
      '      margin-bottom: 20px;' &&
      '      text-align: center;' &&
      '    }' &&
      '    .action-selector {' &&
      '      display: grid;' &&
      '      grid-template-columns: 1fr 1fr;' &&
      '      gap: 8px;' &&
      '      margin-bottom: 20px;' &&
      '    }' &&
      '    .radio-card {' &&
      '      border: 1px solid var(--border);' &&
      '      border-radius: 8px;' &&
      '      padding: 10px 12px;' &&
      '      cursor: pointer;' &&
      '      text-align: center;' &&
      '      font-size: 13px;' &&
      '      font-weight: 500;' &&
      '      color: var(--text-muted);' &&
      '      transition: all 0.15s ease;' &&
      '    }' &&
      '    .radio-card input { display: none; }' &&
      '    .radio-card.selected {' &&
      '      border-color: var(--primary);' &&
      '      background-color: #f1f5f9;' &&
      '      color: var(--text-main);' &&
      '      font-weight: 600;' &&
      '    }' &&
      '    .form-group {' &&
      '      margin-bottom: 16px;' &&
      '    }' &&
      '    .form-group label {' &&
      '      display: block;' &&
      '      font-size: 13px;' &&
      '      font-weight: 500;' &&
      '      margin-bottom: 6px;' &&
      '      color: var(--text-main);' &&
      '    }' &&
      '    .form-group input {' &&
      '      width: 100%;' &&
      '      padding: 10px 12px;' &&
      '      border: 1px solid var(--border);' &&
      '      border-radius: 6px;' &&
      '      font-size: 14px;' &&
      '      outline: none;' &&
      '      background: #ffffff;' &&
      '      transition: border-color 0.15s ease;' &&
      '    }' &&
      '    .form-group input:focus {' &&
      '      border-color: var(--primary);' &&
      '    }' &&
      '    .hint {' &&
      '      display: block;' &&
      '      font-size: 12px;' &&
      '      color: var(--text-muted);' &&
      '      margin-top: 4px;' &&
      '    }' &&
      '    .info-note {' &&
      '      font-size: 12px;' &&
      '      color: var(--text-muted);' &&
      '      margin-bottom: 20px;' &&
      '      line-height: 1.4;' &&
      '    }' &&
      '    .btn {' &&
      '      width: 100%;' &&
      '      padding: 11px 16px;' &&
      '      border: 1px solid transparent;' &&
      '      border-radius: 6px;' &&
      '      cursor: pointer;' &&
      '      font-weight: 500;' &&
      '      font-size: 14px;' &&
      '      text-align: center;' &&
      '      text-decoration: none;' &&
      '      display: inline-block;' &&
      '      transition: background-color 0.15s ease;' &&
      '    }' &&
      '    .btn-primary {' &&
      '      background: var(--primary);' &&
      '      color: #ffffff;' &&
      '    }' &&
      '    .btn-primary:hover { background: var(--primary-hover); }' &&
      '    .btn-secondary {' &&
      '      background: #ffffff;' &&
      '      border-color: var(--border);' &&
      '      color: var(--text-main);' &&
      '      width: auto;' &&
      '      padding: 8px 18px;' &&
      '    }' &&
      '    .btn-secondary:hover { background: #f8fafc; }' &&
      '    .alert {' &&
      '      padding: 10px 14px;' &&
      '      border-radius: 6px;' &&
      '      font-size: 13px;' &&
      '      margin-bottom: 16px;' &&
      '      line-height: 1.4;' &&
      '    }' &&
      '    .alert-error {' &&
      '      background-color: #fef2f2;' &&
      '      border: 1px solid #fee2e2;' &&
      '      color: #991b1b;' &&
      '    }' &&
      '    .rules-list {' &&
      '      list-style: none;' &&
      '      font-size: 12px;' &&
      '      color: var(--text-muted);' &&
      '      margin: 12px 0 18px 0;' &&
      '      padding: 10px 12px;' &&
      '      background: #f8fafc;' &&
      '      border: 1px solid var(--border);' &&
      '      border-radius: 6px;' &&
      '    }' &&
      '    .rules-list li { margin-bottom: 4px; }' &&
      '    .rules-list li:last-child { margin-bottom: 0; }' &&
      '    .rules-list li.valid { color: var(--success); font-weight: 500; }' &&
      '    .msg-box { text-align: center; }' &&
      '    .msg-icon {' &&
      '      font-size: 36px;' &&
      '      line-height: 1;' &&
      '      margin-bottom: 16px;' &&
      '    }' &&
      '    .text-success { color: var(--success); }' &&
      '    .text-warning { color: var(--warning); }' &&
      '    .text-error { color: var(--error); }' &&
      '    .text-info { color: var(--primary); }' &&
      '    .msg-heading {' &&
      '      font-size: 18px;' &&
      '      font-weight: 600;' &&
      '      margin-bottom: 8px;' &&
      '      color: var(--text-main);' &&
      '    }' &&
      '    .msg-text {' &&
      '      font-size: 14px;' &&
      '      color: var(--text-muted);' &&
      '      line-height: 1.5;' &&
      '      margin-bottom: 16px;' &&
      '    }' &&
      '    .msg-detail {' &&
      '      background: #f8fafc;' &&
      '      border: 1px solid var(--border);' &&
      '      border-radius: 6px;' &&
      '      padding: 12px 14px;' &&
      '      font-size: 13px;' &&
      '      color: var(--text-muted);' &&
      '      text-align: left;' &&
      '      line-height: 1.5;' &&
      '    }' &&
      '    .footer {' &&
      '      margin-top: 24px;' &&
      '      text-align: center;' &&
      '      font-size: 12px;' &&
      '      color: var(--text-muted);' &&
      '    }' &&
      '  </style>' &&
      '</head>' &&
      '<body>' &&
      '  <div class="card">' &&
      '    <div class="card-header">' &&
      '      <h1>' && lv_esc_card_t && '</h1>' &&
      lv_sub_html &&
      '    </div>' &&
      '    <div class="card-body">' &&
      content &&
      '    </div>' &&
      '    <div class="footer">' &&
      '      &copy; ' && sy-datum(4) && ' SAP Self-Service' &&
      '    </div>' &&
      '  </div>' &&
      '  <script>' &&
      '    function updateActionUI(val) {' &&
      '      document.getElementById("opt_reset_pwd").classList.toggle("selected", val === "RESET_PWD");' &&
      '      document.getElementById("opt_unlock").classList.toggle("selected", val === "UNLOCK");' &&
      '      const btn = document.getElementById("btnSubmit");' &&
      '      if (btn) {' &&
      '        btn.innerText = val === "UNLOCK" ? "Send Unlock Link" : "Send Reset Link";' &&
      '      }' &&
      '    }' &&
      '    function checkStrength(p) {' &&
      '      document.getElementById("r_len").className = p.length >= 10 ? "valid" : "";' &&
      '      document.getElementById("r_upper").className = /[A-Z]/.test(p) ? "valid" : "";' &&
      '      document.getElementById("r_lower").className = /[a-z]/.test(p) ? "valid" : "";' &&
      '      document.getElementById("r_num").className = /[0-9]/.test(p) ? "valid" : "";' &&
      '      document.getElementById("r_spec").className = /[^a-zA-Z0-9]/.test(p) ? "valid" : "";' &&
      '      checkMatch();' &&
      '    }' &&
      '    function checkMatch() {' &&
      '      const p1 = document.getElementById("new_password")?.value || "";' &&
      '      const p2 = document.getElementById("confirm_password")?.value || "";' &&
      '      const msg = document.getElementById("matchMsg");' &&
      '      if (!msg || !p2) { if (msg) msg.innerText = ""; return; }' &&
      '      if (p1 === p2) {' &&
      '        msg.style.color = "var(--success)";' &&
      '        msg.innerText = "✓ Passwords match";' &&
      '      } else {' &&
      '        msg.style.color = "var(--error)";' &&
      '        msg.innerText = "✗ Passwords do not match";' &&
      '      }' &&
      '    }' &&
      '    function validatePwdForm() {' &&
      '      const p1 = document.getElementById("new_password")?.value || "";' &&
      '      const p2 = document.getElementById("confirm_password")?.value || "";' &&
      '      if (p1.length < 10 || !/[A-Z]/.test(p1) || !/[a-z]/.test(p1) || !/[0-9]/.test(p1) || !/[^a-zA-Z0-9]/.test(p1)) {' &&
      '        alert("Password must be at least 10 characters and include uppercase, lowercase, numbers, and special characters.");' &&
      '        return false;' &&
      '      }' &&
      '      if (p1 !== p2) {' &&
      '        alert("Passwords do not match.");' &&
      '        return false;' &&
      '      }' &&
      '      return true;' &&
      '    }' &&
      '  </script>' &&
      '</body>' &&
      '</html>'.
  ENDMETHOD.


  METHOD render_response.
    DATA(lv_reason) = SWITCH string( status_code
      WHEN 200 THEN 'OK'
      WHEN 400 THEN 'Bad Request'
      WHEN 403 THEN 'Forbidden'
      WHEN 405 THEN 'Method Not Allowed'
      WHEN 429 THEN 'Too Many Requests'
      WHEN 500 THEN 'Internal Server Error'
      ELSE 'OK' ).

    server->response->set_status( code = status_code reason = lv_reason ).
    server->response->set_header_field( name = 'content-type' value = content_type ).
    server->response->set_header_field( name = 'cache-control' value = 'no-store, no-cache, must-revalidate, max-age=0' ).
    server->response->set_header_field( name = 'pragma' value = 'no-cache' ).
    server->response->set_header_field( name = 'x-content-type-options' value = 'nosniff' ).
    server->response->set_header_field( name = 'x-frame-options' value = 'DENY' ).
    server->response->set_header_field( name = 'referrer-policy' value = 'no-referrer' ).
    server->response->set_header_field( name = 'strict-transport-security' value = 'max-age=31536000; includeSubDomains' ).
    server->response->set_header_field(
      name  = 'content-security-policy'
      value = 'default-src ''none''; style-src ''unsafe-inline''; script-src ''unsafe-inline''; form-action ''self''; frame-ancestors ''none''; base-uri ''self''' ).
    server->response->set_cdata( body ).
  ENDMETHOD.


  METHOD is_same_origin_post.
    DATA: lv_sec_site TYPE string,
          lv_origin   TYPE string,
          lv_orig_h   TYPE string,
          lv_req_host TYPE string,
          lv_dummy    TYPE string.

    is_ok = abap_true.

    " Modern browsers send Sec-Fetch-Site on every POST
    lv_sec_site = to_lower( server->request->get_header_field( 'sec-fetch-site' ) ).
    CONDENSE lv_sec_site NO-GAPS.
    IF lv_sec_site IS NOT INITIAL AND lv_sec_site <> 'same-origin' AND lv_sec_site <> 'none'.
      is_ok = abap_false.
      RETURN.
    ENDIF.

    " Validate Origin header host against request host when present
    lv_origin = to_lower( server->request->get_header_field( 'origin' ) ).
    CONDENSE lv_origin NO-GAPS.
    IF lv_origin IS NOT INITIAL AND lv_origin <> 'null'.
      lv_orig_h = lv_origin.
      REPLACE FIRST OCCURRENCE OF 'https://' IN lv_orig_h WITH ''.
      REPLACE FIRST OCCURRENCE OF 'http://'  IN lv_orig_h WITH ''.
      IF lv_orig_h CS '/'.
        SPLIT lv_orig_h AT '/' INTO lv_orig_h lv_dummy.
      ENDIF.
      IF lv_orig_h CS ':'.
        SPLIT lv_orig_h AT ':' INTO lv_orig_h lv_dummy.
      ENDIF.

      lv_req_host = to_lower( server->request->get_header_field( 'x-forwarded-host' ) ).
      IF lv_req_host IS INITIAL.
        lv_req_host = to_lower( server->request->get_header_field( 'host' ) ).
      ENDIF.
      IF lv_req_host CS ','.
        SPLIT lv_req_host AT ',' INTO lv_req_host lv_dummy.
      ENDIF.
      IF lv_req_host CS ':'.
        SPLIT lv_req_host AT ':' INTO lv_req_host lv_dummy.
      ENDIF.
      CONDENSE lv_req_host NO-GAPS.

      IF lv_req_host IS NOT INITIAL AND lv_orig_h <> lv_req_host.
        is_ok = abap_false.
        RETURN.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD is_trusted_proxy_ip.
    DATA: lv_ip TYPE string.
    lv_ip = ip_str.
    CONDENSE lv_ip NO-GAPS.

    IF lv_ip IS INITIAL
       OR lv_ip = '::1'
       OR lv_ip CP '127.*'
       OR lv_ip CP '10.*'
       OR lv_ip CP '192.168.*'.
      trusted = abap_true.
      RETURN.
    ENDIF.

    FIND PCRE '^172\.(1[6-9]|2[0-9]|3[0-1])\.' IN lv_ip.
    IF sy-subrc = 0.
      trusted = abap_true.
      RETURN.
    ENDIF.

    trusted = abap_false.
  ENDMETHOD.


  METHOD increment_token_attempts.
    CLEAR attempts.
    " Atomic SQL increment prevents read-modify-write race conditions
    UPDATE zsspr_tokens
      SET attempts = attempts + 1
      WHERE token = @token_hash.
    COMMIT WORK.

    SELECT SINGLE attempts FROM zsspr_tokens
      WHERE token = @token_hash
      INTO @attempts.
  ENDMETHOD.


  METHOD generate_secure_token.
    DATA: lv_rnd_x TYPE xstring,
          lv_hex   TYPE string.

    CLEAR token.

    " H3: Use SAP cryptographic random generator (CSPRNG, 32 bytes = 256 bits)
    CALL FUNCTION 'GENERATE_SEC_RANDOM'
      EXPORTING
        length         = 32
      IMPORTING
        random         = lv_rnd_x
      EXCEPTIONS
        invalid_length = 1
        no_memory      = 2
        internal_error = 3
        OTHERS         = 4.

    IF sy-subrc = 0 AND xstrlen( lv_rnd_x ) = 32.
      lv_hex = |{ lv_rnd_x }|.
      CONDENSE lv_hex NO-GAPS.
      token = to_upper( lv_hex ).
    ENDIF.
  ENDMETHOD.


  METHOD hash_token.
    DATA: lv_hash TYPE string,
          lv_in   TYPE string.

    CLEAR token_hash.
    IF token IS INITIAL.
      RETURN.
    ENDIF.

    lv_in = to_upper( token ).
    CONDENSE lv_in NO-GAPS.

    TRY.
        cl_abap_message_digest=>calculate_hash_for_char(
          EXPORTING
            if_algorithm  = 'SHA256'
            if_data       = lv_in
          IMPORTING
            ef_hashstring = lv_hash ).
        token_hash = to_upper( lv_hash ).
      CATCH cx_abap_message_digest.
        CLEAR token_hash.
    ENDTRY.
  ENDMETHOD.


  METHOD is_production_system.
    " Check if SAP System ID (SID) contains 'P' (Production)
    IF sy-sysid CS 'P'.
      is_prod = abap_true.
    ELSE.
      is_prod = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD get_client_ip.
    DATA: lv_remote TYPE string,
          lv_xff    TYPE string,
          lt_hops   TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    lv_remote = server->request->get_header_field( '~remote_addr' ).
    CONDENSE lv_remote NO-GAPS.

    " Only trust forwarded headers when the TCP peer is a trusted internal proxy / Web Dispatcher
    IF me->is_trusted_proxy_ip( lv_remote ) = abap_true.
      lv_xff = server->request->get_header_field( 'x-forwarded-for' ).
      IF lv_xff IS NOT INITIAL.
        SPLIT lv_xff AT ',' INTO TABLE lt_hops.
        IF lt_hops IS NOT INITIAL.
          ip_str = lt_hops[ lines( lt_hops ) ].
        ENDIF.
        CONDENSE ip_str NO-GAPS.
      ENDIF.

      IF ip_str IS INITIAL.
        ip_str = server->request->get_header_field( 'x-real-ip' ).
        CONDENSE ip_str NO-GAPS.
      ENDIF.
    ENDIF.

    IF ip_str IS INITIAL.
      ip_str = lv_remote.
    ENDIF.

    " Validate IPv4/IPv6 characters (fallback 'UNKNOWN' remains subject to IP rate limiting)
    FIND PCRE '^[0-9a-fA-F.:]+$' IN ip_str.
    IF sy-subrc <> 0 OR strlen( ip_str ) > 45.
      ip_str = 'UNKNOWN'.
    ENDIF.
  ENDMETHOD.


  METHOD get_base_url.
    DATA: lv_host       TYPE string,
          lv_hdr_host   TYPE string,
          lv_cfg_host   TYPE tvarvc-low,
          lt_loc_hosts  TYPE STANDARD TABLE OF httpurlloc-host WITH EMPTY KEY,
          lv_remote     TYPE string,
          lv_proto      TYPE string,
          lv_path       TYPE string,
          lv_dummy      TYPE string,
          lv_port_part  TYPE string,
          lv_allowed    TYPE abap_bool.

    " 1a. Optional administrator-configured canonical host in TVARVC (strongest anti-Host-Injection)
    SELECT SINGLE low FROM tvarvc
      WHERE name = 'ZSSPR_BASE_HOST'
        AND type = 'P'
      INTO @lv_cfg_host.
    IF sy-subrc = 0 AND lv_cfg_host IS NOT INITIAL.
      lv_host = lv_cfg_host.
      CONDENSE lv_host NO-GAPS.
    ENDIF.

    " 1b. Read incoming proxy/host header for validation against server-side allowlist
    IF lv_host IS INITIAL.
      lv_remote = server->request->get_header_field( '~remote_addr' ).
      CONDENSE lv_remote NO-GAPS.

      IF me->is_trusted_proxy_ip( lv_remote ) = abap_true.
        lv_hdr_host = server->request->get_header_field( 'x-forwarded-host' ).
      ENDIF.
      IF lv_hdr_host IS INITIAL.
        lv_hdr_host = server->request->get_header_field( 'host' ).
      ENDIF.
      IF lv_hdr_host CS ','.
        SPLIT lv_hdr_host AT ',' INTO lv_hdr_host lv_dummy.
      ENDIF.
      CONDENSE lv_hdr_host NO-GAPS.
      IF lv_hdr_host CS ':'.
        SPLIT lv_hdr_host AT ':' INTO lv_hdr_host lv_port_part.
      ENDIF.
      lv_hdr_host = to_lower( lv_hdr_host ).

      " Prefer SAP HTTPURLLOC allowlist when maintained
      SELECT host FROM httpurlloc
        WHERE ( applicatn = '/*' OR applicatn = '/SAP/BC/*' OR applicatn = '/RESET*' )
          AND host IS NOT INITIAL
        INTO TABLE @lt_loc_hosts.

      IF lt_loc_hosts IS NOT INITIAL.
        LOOP AT lt_loc_hosts INTO DATA(lv_loc_h).
          DATA(lv_loc_low) = to_lower( CONV string( lv_loc_h ) ).
          CONDENSE lv_loc_low NO-GAPS.
          IF lv_loc_low CS ':'.
            SPLIT lv_loc_low AT ':' INTO lv_loc_low lv_port_part.
          ENDIF.
          IF lv_hdr_host IS NOT INITIAL AND lv_hdr_host = lv_loc_low.
            lv_host    = lv_loc_low.
            lv_allowed = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_allowed = abap_false.
          lv_host = to_lower( CONV string( lt_loc_hosts[ 1 ] ) ).
          CONDENSE lv_host NO-GAPS.
          IF lv_host CS ':'.
            SPLIT lv_host AT ':' INTO lv_host lv_port_part.
          ENDIF.
        ENDIF.
      ELSEIF me->is_trusted_proxy_ip( lv_remote ) = abap_true AND lv_hdr_host IS NOT INITIAL.
        " Behind trusted internal reverse proxy when HTTPURLLOC is not maintained
        lv_host = lv_hdr_host.
      ELSE.
        " Direct connection: always use ICM ~server_name (never untrusted client Host header)
        lv_host = server->request->get_header_field( '~server_name' ).
      ENDIF.
    ENDIF.

    IF lv_host IS INITIAL.
      lv_host = server->request->get_header_field( '~server_name' ).
    ENDIF.

    IF lv_host CS ':'.
      SPLIT lv_host AT ':' INTO lv_host lv_port_part.
    ENDIF.
    CONDENSE lv_host NO-GAPS.

    " Strict validation: hostname must match alphanumeric domain pattern
    FIND PCRE '^[a-zA-Z0-9.-]+$' IN lv_host.
    IF sy-subrc <> 0.
      lv_host = 'localhost'.
    ENDIF.

    " 2. Protocol: Default to HTTPS for Web Dispatcher / reverse proxy
    lv_proto = 'https'.

    " 3. Path: preserve external route (strictly validated against path injection)
    lv_path = server->request->get_header_field( '~script_name' ).
    IF lv_path IS INITIAL.
      lv_path = server->request->get_header_field( '~path' ).
    ENDIF.
    FIND PCRE '^/[A-Za-z0-9_/-]+$' IN lv_path.
    IF sy-subrc <> 0.
      lv_path = '/reset'.
    ENDIF.

    url_str = lv_proto && '://' && to_lower( lv_host ) && lv_path.
  ENDMETHOD.


  METHOD is_protected_account.
    DATA: lv_user_up TYPE bapibname-bapibname.
    lv_user_up = to_upper( bname ).

    " Critical system users
    IF lv_user_up = 'SAP*' OR lv_user_up = 'DDIC' OR lv_user_up = 'TMSADM'
       OR lv_user_up = 'EARLYWATCH' OR lv_user_up = 'SAPCPIC'.
      protected = abap_true.
      RETURN.
    ENDIF.

    " Check user group in USR02
    SELECT SINGLE class FROM usr02 INTO @DATA(lv_user_grp)
      WHERE bname = @lv_user_up.
    IF sy-subrc = 0 AND ( lv_user_grp = 'SUPER' OR lv_user_grp = 'ADMIN' ).
      protected = abap_true.
      RETURN.
    ENDIF.

    protected = abap_false.
  ENDMETHOD.


  METHOD get_user_email_and_name.
    DATA: ls_address   TYPE bapiaddr3,
          ls_logondata TYPE bapilogond,
          ls_islocked  TYPE bapislockd,
          lt_return    TYPE STANDARD TABLE OF bapiret2,
          lt_smtp      TYPE STANDARD TABLE OF bapiadsmtp,
          lv_uflag     TYPE usr02-uflag,
          lv_admin_bit TYPE i.

    CLEAR: email, fullname, user_found, is_dialog, is_locked, is_admin_locked, is_expired.

    " 1. Strict existence check in USR02
    SELECT SINGLE uflag FROM usr02
      WHERE bname = @bname
      INTO @lv_uflag.

    IF sy-subrc <> 0.
      user_found = abap_false.
      RETURN.
    ENDIF.

    user_found = abap_true.

    " UFLAG bitmask in USR02:
    "   32  = Locked globally by CUA administrator
    "   64  = Locked locally by system administrator
    "   128 = Locked due to incorrect logon attempts
    lv_admin_bit = lv_uflag MOD 128.
    IF lv_admin_bit >= 32.
      is_admin_locked = abap_true.
    ENDIF.
    IF lv_uflag >= 128.
      is_locked = abap_true.
    ENDIF.

    " 2. Read user master detail via standard BAPI
    CALL FUNCTION 'BAPI_USER_GET_DETAIL'
      EXPORTING
        username  = bname
      IMPORTING
        logondata = ls_logondata
        address   = ls_address
        islocked  = ls_islocked
      TABLES
        addsmtp   = lt_smtp
        return    = lt_return.

    LOOP AT lt_return INTO DATA(ls_det_ret) WHERE type CA 'EA'.
      " Fail closed if user detail cannot be retrieved
      is_dialog = abap_false.
      RETURN.
    ENDLOOP.

    " H1: Distinguish Administrator Locks (local_lock / glob_lock) from Wrong Logon Locks (wrng_logon)
    IF ls_islocked-local_lock = 'L' OR ls_islocked-local_lock = 'X'
       OR ls_islocked-glob_lock = 'L' OR ls_islocked-glob_lock = 'X'.
      is_admin_locked = abap_true.
    ENDIF.

    IF ls_islocked-wrng_logon = 'L' OR ls_islocked-wrng_logon = 'X'.
      is_locked = abap_true.
    ENDIF.

    " L1: Check user account validity period (GLTGV .. GLTGB)
    IF ( ls_logondata-gltgv IS NOT INITIAL AND ls_logondata-gltgv <> '00000000' AND ls_logondata-gltgv > sy-datum )
       OR ( ls_logondata-gltgb IS NOT INITIAL AND ls_logondata-gltgb <> '00000000' AND ls_logondata-gltgb < sy-datum ).
      is_expired = abap_true.
    ENDIF.

    email    = ls_address-e_mail.
    fullname = ls_address-lastname.
    IF email IS INITIAL.
      READ TABLE lt_smtp INTO DATA(ls_smtp) INDEX 1.
      IF sy-subrc = 0.
        email = ls_smtp-e_mail.
      ENDIF.
    ENDIF.

    IF ls_logondata-ustyp = 'A'.
      is_dialog = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD mask_email.
    DATA: lv_user_part TYPE string,
          lv_dom_part  TYPE string,
          lv_len       TYPE i.

    SPLIT email AT '@' INTO lv_user_part lv_dom_part.
    lv_len = strlen( lv_user_part ).
    IF lv_len = 0.
      masked = '***@' && lv_dom_part.
    ELSEIF lv_len <= 2.
      masked = lv_user_part(1) && '***@' && lv_dom_part.
    ELSE.
      DATA(lv_last_idx) = lv_len - 1.
      masked = lv_user_part(1) && '***' && lv_user_part+lv_last_idx(1) && '@' && lv_dom_part.
    ENDIF.
  ENDMETHOD.


  METHOD send_notification_email.
    DATA: lo_send_request TYPE REF TO cl_bcs,
          lo_document     TYPE REF TO cl_document_bcs,
          lo_recipient    TYPE REF TO if_recipient_bcs,
          lt_body_solix   TYPE solix_tab,
          lv_body_size    TYPE so_obj_len,
          lv_addr         TYPE ad_smtpadr,
          lv_subj         TYPE so_obj_des,
          lx_bcs          TYPE REF TO cx_bcs.

    CLEAR sent_ok.

    IF recipient_email IS INITIAL.
      RETURN.
    ENDIF.

    lv_addr = recipient_email.
    lv_subj = subject.

    TRY.
        lo_send_request = cl_bcs=>create_persistent( ).

        cl_bcs_convert=>string_to_solix(
          EXPORTING
            iv_string   = html_content
            iv_codepage = '4110'
          IMPORTING
            et_solix    = lt_body_solix
            ev_size     = lv_body_size ).

        lo_document = cl_document_bcs=>create_document(
                        i_type    = 'HTM'
                        i_hex     = lt_body_solix
                        i_length  = lv_body_size
                        i_subject = lv_subj ).

        lo_send_request->set_document( lo_document ).

        lo_recipient = cl_cam_address_bcs=>create_internet_address( lv_addr ).
        lo_send_request->add_recipient( lo_recipient ).

        lo_send_request->set_send_immediately( abap_true ).
        sent_ok = lo_send_request->send( i_with_error_screen = 'N' ).
        COMMIT WORK.

      CATCH cx_bcs INTO lx_bcs.
        sent_ok = abap_false.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
