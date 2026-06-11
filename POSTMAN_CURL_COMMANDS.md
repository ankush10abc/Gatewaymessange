# 📱 POSTMAN CURL COMMANDS - ALL NEW SYNC APIs

**Date:** June 6, 2026
**For Testing:** All 6 new offline-sync APIs

---

## ⚙️ SETUP FIRST

### 1. Get Sanctum Token (For Auth)
```bash
curl --location 'http://localhost:8000/api/login' \
--header 'Content-Type: application/json' \
--data-raw '{
  "email": "teacher@example.com",
  "password": "password"
}'
```

**Response:**
```json
{
  "success": true,
  "token": "YOUR_SANCTUM_TOKEN_HERE",
  "user": { ... }
}
```

**Save the token** - You'll need it for APIs 1-5.

### 2. Set Postman Variables
```
baseUrl = http://localhost:8000/api
token = YOUR_SANCTUM_TOKEN_HERE
```

---

## 🚀 API 1: BATCH MESSAGE SEND

### CURL Command
```bash
curl --location 'http://localhost:8000/api/messages/batch-send' \
--header 'Authorization: Bearer YOUR_SANCTUM_TOKEN_HERE' \
--header 'Content-Type: application/json' \
--header 'Accept: application/json' \
--data-raw '{
  "messages": [
    {
      "temp_id": "temp_1705315800000",
      "chat_id": 1,
      "chat_type": "group",
      "type": "text",
      "message": "Hello, this is message 1",
      "firebase_key": "firebase_msg_001",
      "client_timestamp": "2026-06-06T10:30:00Z"
    },
    {
      "temp_id": "temp_1705315800001",
      "chat_id": 1,
      "chat_type": "group",
      "type": "text",
      "content": "Hello, this is message 2 (using content field)",
      "firebase_key": "firebase_msg_002",
      "client_timestamp": "2026-06-06T10:31:00Z"
    },
    {
      "temp_id": "temp_1705315800002",
      "chat_id": 2,
      "chat_type": "user",
      "message_type": "text",
      "message": "Direct message to user",
      "firebase_key": "firebase_msg_003",
      "is_forwarded": false
    }
  ]
}'
```

### In Postman
```
Method: POST
URL: {{baseUrl}}/messages/batch-send
Headers:
  Authorization: Bearer {{token}}
  Content-Type: application/json

Body (raw JSON):
{
  "messages": [
    {
      "temp_id": "temp_1705315800000",
      "chat_id": 1,
      "chat_type": "group",
      "type": "text",
      "message": "Hello, this is message 1",
      "firebase_key": "firebase_msg_001",
      "client_timestamp": "2026-06-06T10:30:00Z"
    }
  ]
}
```

### Expected Response (200 OK)
```json
{
  "success": true,
  "data": {
    "sent": [
      {
        "temp_id": "temp_1705315800000",
        "id": "501",
        "msgId": "501",
        "status": "sent",
        "firebase_id": "firebase_msg_001",
        "created_at": "2026-06-06T10:30:00+00:00"
      },
      {
        "temp_id": "temp_1705315800001",
        "id": "502",
        "msgId": "502",
        "status": "sent",
        "firebase_id": "firebase_msg_002",
        "created_at": "2026-06-06T10:31:00+00:00"
      }
    ],
    "failed": [
      {
        "temp_id": "temp_1705315800002",
        "error": "Group not found",
        "error_code": "CHAT_NOT_FOUND"
      }
    ],
    "total_sent": 2,
    "total_failed": 1
  },
  "message": "2 messages sent, 1 failed"
}
```

### Test Cases

#### ✅ Test 1: Send 3 Group Messages
```bash
curl --location 'http://localhost:8000/api/messages/batch-send' \
--header 'Authorization: Bearer {{token}}' \
--header 'Content-Type: application/json' \
--data-raw '{
  "messages": [
    {
      "temp_id": "msg_001",
      "chat_id": 1,
      "chat_type": "group",
      "type": "text",
      "message": "Message 1",
      "firebase_key": "key_001"
    },
    {
      "temp_id": "msg_002",
      "chat_id": 1,
      "chat_type": "group",
      "type": "text",
      "message": "Message 2",
      "firebase_key": "key_002"
    },
    {
      "temp_id": "msg_003",
      "chat_id": 1,
      "chat_type": "group",
      "type": "text",
      "message": "Message 3",
      "firebase_key": "key_003"
    }
  ]
}'
```

#### ✅ Test 2: Send Direct Message
```bash
curl --location 'http://localhost:8000/api/messages/batch-send' \
--header 'Authorization: Bearer {{token}}' \
--header 'Content-Type: application/json' \
--data-raw '{
  "messages": [
    {
      "temp_id": "direct_msg_001",
      "chat_id": 5,
      "chat_type": "user",
      "type": "text",
      "message": "Hello, this is a direct message",
      "firebase_key": "direct_key_001"
    }
  ]
}'
```

#### ✅ Test 3: Send 5 Messages with Replies
```bash
curl --location 'http://localhost:8000/api/messages/batch-send' \
--header 'Authorization: Bearer {{token}}' \
--header 'Content-Type: application/json' \
--data-raw '{
  "messages": [
    {
      "temp_id": "msg_reply_001",
      "chat_id": 1,
      "chat_type": "group",
      "type": "text",
      "message": "Original message",
      "firebase_key": "key_reply_001"
    },
    {
      "temp_id": "msg_reply_002",
      "chat_id": 1,
      "chat_type": "group",
      "type": "text",
      "message": "Reply to message",
      "reply_to_message_id": 50,
      "firebase_key": "key_reply_002"
    }
  ]
}'
```

---

## 🔄 API 2: INCREMENTAL MESSAGE SYNC

### CURL Command
```bash
curl --location 'http://localhost:8000/api/messages/sync?chat_id=1&chat_type=group&since=2026-06-05T00:00:00Z&limit=100' \
--header 'Authorization: Bearer YOUR_SANCTUM_TOKEN_HERE' \
--header 'Accept: application/json'
```

### In Postman
```
Method: GET
URL: {{baseUrl}}/messages/sync?chat_id=1&chat_type=group&since=2026-06-05T00:00:00Z&limit=100
Headers:
  Authorization: Bearer {{token}}
  Accept: application/json
```

### Query Parameters Explained
```
chat_id = 1                          (required)
chat_type = group                    (required: "group" or "user")
since = 2026-06-05T00:00:00Z        (required: ISO 8601 timestamp)
limit = 100                          (optional: 1-500, default 100)
```

### Expected Response (200 OK)
```json
{
  "success": true,
  "data": {
    "messages": [
      {
        "id": "501",
        "msgId": "501",
        "chat_id": "1",
        "sender_id": "5",
        "sender_name": "Teacher Name",
        "profile_picture_url": "http://localhost:8000/storage/profile_pictures/teacher.jpg",
        "content": "New message content",
        "type": "text",
        "file_path": null,
        "file_name": null,
        "file_size": null,
        "reply_to_message_id": null,
        "reply_to_message": null,
        "is_forwarded": false,
        "firebase_id": "firebase_msg_001",
        "created_at": "2026-06-06T10:30:00+00:00",
        "updated_at": "2026-06-06T10:30:00+00:00",
        "read_at": null
      },
      {
        "id": "502",
        "msgId": "502",
        "chat_id": "1",
        "sender_id": "6",
        "sender_name": "Another Teacher",
        "profile_picture_url": null,
        "content": "Reply to something",
        "type": "text",
        "file_path": null,
        "file_name": null,
        "file_size": null,
        "reply_to_message_id": "501",
        "reply_to_message": {
          "id": "501",
          "content": "New message content",
          "sender": {
            "id": "5",
            "name": "Teacher Name"
          }
        },
        "is_forwarded": false,
        "firebase_id": "firebase_msg_002",
        "created_at": "2026-06-06T10:31:00+00:00",
        "updated_at": "2026-06-06T10:31:00+00:00",
        "read_at": null
      }
    ],
    "deleted_message_ids": ["450", "451"],
    "updated_messages": [
      {
        "id": "480",
        "msgId": "480",
        "content": "Edited message content",
        "updated_at": "2026-06-06T11:00:00+00:00"
      }
    ],
    "has_more": false,
    "synced_at": "2026-06-06T11:30:00+00:00",
    "next_page_token": null
  }
}
```

### Test Cases

#### ✅ Test 1: Get Group Messages Since Today
```bash
curl --location 'http://localhost:8000/api/messages/sync?chat_id=1&chat_type=group&since=2026-06-06T00:00:00Z' \
--header 'Authorization: Bearer {{token}}'
```

#### ✅ Test 2: Get Direct Messages with Limit
```bash
curl --location 'http://localhost:8000/api/messages/sync?chat_id=5&chat_type=user&since=2026-06-01T00:00:00Z&limit=50' \
--header 'Authorization: Bearer {{token}}'
```

#### ✅ Test 3: Get Only Recent Messages (Last 1 hour)
```bash
curl --location 'http://localhost:8000/api/messages/sync?chat_id=1&chat_type=group&since=2026-06-06T10:00:00Z' \
--header 'Authorization: Bearer {{token}}'
```

---

## 💬 API 3: INCREMENTAL CHAT LIST SYNC

### CURL Command
```bash
curl --location 'http://localhost:8000/api/chats/sync?since=2026-06-05T00:00:00Z&limit=50' \
--header 'Authorization: Bearer YOUR_SANCTUM_TOKEN_HERE' \
--header 'Accept: application/json'
```

### In Postman
```
Method: GET
URL: {{baseUrl}}/chats/sync?since=2026-06-05T00:00:00Z&limit=50
Headers:
  Authorization: Bearer {{token}}
  Accept: application/json
```

### Query Parameters
```
since = 2026-06-05T00:00:00Z   (optional: ISO 8601, default 30 days ago)
limit = 50                      (optional: 1-200, default 50)
```

### Expected Response (200 OK)
```json
{
  "success": true,
  "data": {
    "new_chats": [
      {
        "id": "15",
        "type": "group",
        "name": "Class A - 2026",
        "profile_picture": "http://localhost:8000/storage/groups/class_a.jpg",
        "last_message": "Welcome to the class!",
        "last_message_time": "2026-06-06T10:30:00+00:00",
        "last_read_at": "2026-06-06T09:00:00+00:00",
        "unread_count": 5,
        "is_pinned": false,
        "attendance_group": false,
        "member_count": 30,
        "created_at": "2026-06-06T08:00:00+00:00",
        "updated_at": "2026-06-06T08:00:00+00:00"
      }
    ],
    "updated_chats": [
      {
        "id": "1",
        "type": "group",
        "name": "Class B",
        "profile_picture": null,
        "last_message": "New assignment posted",
        "last_message_time": "2026-06-06T10:40:00+00:00",
        "last_read_at": "2026-06-06T08:00:00+00:00",
        "unread_count": 12,
        "is_pinned": true,
        "attendance_group": false,
        "member_count": 28,
        "created_at": "2026-05-01T00:00:00+00:00",
        "updated_at": "2026-06-06T10:40:00+00:00"
      },
      {
        "id": "5",
        "type": "user",
        "name": "John Teacher",
        "actual_role": "teacher",
        "profile_picture": "http://localhost:8000/storage/profile_pictures/john.jpg",
        "last_message": "Thanks for your help",
        "last_message_time": "2026-06-06T10:20:00+00:00",
        "last_read_at": "2026-06-06T10:20:00+00:00",
        "unread_count": 0,
        "is_pinned": false,
        "created_at": "2026-05-15T00:00:00+00:00",
        "updated_at": "2026-06-06T10:20:00+00:00"
      }
    ],
    "deleted_chat_ids": [],
    "synced_at": "2026-06-06T11:30:00+00:00"
  }
}
```

### Test Cases

#### ✅ Test 1: Get All Chats Since Yesterday
```bash
curl --location 'http://localhost:8000/api/chats/sync?since=2026-06-05T00:00:00Z' \
--header 'Authorization: Bearer {{token}}'
```

#### ✅ Test 2: Get Only Recent Chats (Last 1 hour)
```bash
curl --location 'http://localhost:8000/api/chats/sync?since=2026-06-06T10:00:00Z' \
--header 'Authorization: Bearer {{token}}'
```

#### ✅ Test 3: Get Limited Number of Chats
```bash
curl --location 'http://localhost:8000/api/chats/sync?since=2026-06-01T00:00:00Z&limit=20' \
--header 'Authorization: Bearer {{token}}'
```

---

## ✓ API 4: BATCH MARK AS READ

### CURL Command (Group Messages)
```bash
curl --location 'http://localhost:8000/api/messages/batch-read' \
--header 'Authorization: Bearer YOUR_SANCTUM_TOKEN_HERE' \
--header 'Content-Type: application/json' \
--header 'Accept: application/json' \
--data-raw '{
  "message_ids": [501, 502, 503, 504, 505],
  "chat_id": 1,
  "chat_type": "group"
}'
```

### CURL Command (Direct Messages)
```bash
curl --location 'http://localhost:8000/api/messages/batch-read' \
--header 'Authorization: Bearer YOUR_SANCTUM_TOKEN_HERE' \
--header 'Content-Type: application/json' \
--header 'Accept: application/json' \
--data-raw '{
  "message_ids": [510, 511, 512],
  "chat_id": 5,
  "chat_type": "user"
}'
```

### In Postman (Group)
```
Method: POST
URL: {{baseUrl}}/messages/batch-read
Headers:
  Authorization: Bearer {{token}}
  Content-Type: application/json

Body (raw JSON):
{
  "message_ids": [501, 502, 503],
  "chat_id": 1,
  "chat_type": "group"
}
```

### Expected Response (200 OK)
```json
{
  "success": true,
  "data": {
    "marked_count": 5,
    "failed_ids": [],
    "marked_at": "2026-06-06T11:30:00+00:00"
  },
  "message": "5 messages marked as read"
}
```

### Test Cases

#### ✅ Test 1: Mark 5 Group Messages as Read
```bash
curl --location 'http://localhost:8000/api/messages/batch-read' \
--header 'Authorization: Bearer {{token}}' \
--header 'Content-Type: application/json' \
--data-raw '{
  "message_ids": [501, 502, 503, 504, 505],
  "chat_id": 1,
  "chat_type": "group"
}'
```

#### ✅ Test 2: Mark 3 Direct Messages as Read
```bash
curl --location 'http://localhost:8000/api/messages/batch-read' \
--header 'Authorization: Bearer {{token}}' \
--header 'Content-Type: application/json' \
--data-raw '{
  "message_ids": [510, 511, 512],
  "chat_id": 5,
  "chat_type": "user"
}'
```

#### ✅ Test 3: Mark 50 Messages as Read
```bash
curl --location 'http://localhost:8000/api/messages/batch-read' \
--header 'Authorization: Bearer {{token}}' \
--header 'Content-Type: application/json' \
--data-raw '{
  "message_ids": [451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500],
  "chat_id": 1,
  "chat_type": "group"
}'
```

---

## 📊 API 5: QUEUE STATUS

### CURL Command
```bash
curl --location 'http://localhost:8000/api/sync/queue-status' \
--header 'Authorization: Bearer YOUR_SANCTUM_TOKEN_HERE' \
--header 'Accept: application/json'
```

### In Postman
```
Method: GET
URL: {{baseUrl}}/sync/queue-status
Headers:
  Authorization: Bearer {{token}}
  Accept: application/json
```

### No Query Parameters (Uses authenticated user)

### Expected Response (200 OK)
```json
{
  "success": true,
  "data": {
    "pending_messages": 12,
    "pending_uploads": 3,
    "failed_messages": 0,
    "oldest_pending_timestamp": "2026-06-06T10:30:00+00:00",
    "queue_size_mb": 0,
    "is_queue_full": false,
    "max_queue_size": 1000
  }
}
```

### Test Cases

#### ✅ Test 1: Check Current Queue Status
```bash
curl --location 'http://localhost:8000/api/sync/queue-status' \
--header 'Authorization: Bearer {{token}}'
```

#### ✅ Test 2: After Batch Send (Should show pending messages)
```bash
# First, send batch of messages
curl --location 'http://localhost:8000/api/messages/batch-send' \
--header 'Authorization: Bearer {{token}}' \
--header 'Content-Type: application/json' \
--data-raw '{"messages": [{"temp_id": "m1", "chat_id": 1, "chat_type": "group", "type": "text", "message": "test"}]}'

# Then check queue
curl --location 'http://localhost:8000/api/sync/queue-status' \
--header 'Authorization: Bearer {{token}}'
```

---

## 📱 API 6: APP VERSION CHECK (Public - No Auth)

### CURL Command
```bash
curl --location 'http://localhost:8000/api/app/version-check?current_version=1.0.23' \
--header 'Accept: application/json'
```

### In Postman
```
Method: GET
URL: {{baseUrl}}/app/version-check?current_version=1.0.23
Headers:
  Accept: application/json
  (NO Authorization needed - Public API)
```

### Query Parameters
```
current_version = 1.0.23   (required: Your current app version)
```

### Expected Response - No Update (200 OK)
```json
{
  "success": true,
  "data": {
    "update_available": false,
    "current_version": "1.0.23",
    "latest_version": "1.0.23",
    "message": "You have the latest version"
  }
}
```

### Expected Response - Optional Update (200 OK)
```json
{
  "success": true,
  "data": {
    "update_available": true,
    "current_version": "1.0.23",
    "latest_version": "1.0.24",
    "update_type": "optional",
    "can_skip": true,
    "block_app_usage": false,
    "force_update_message": null,
    "release_notes": "Bug fixes and performance improvements",
    "download_url": "https://play.google.com/store/apps/details?id=com.gatewayreports.messenger",
    "direct_download_url": "https://example.com/gateway-academy-1.0.24.apk",
    "apk_size_mb": 45,
    "release_date": "2026-06-06",
    "min_supported_version": null
  }
}
```

### Expected Response - Forced Update (200 OK)
```json
{
  "success": true,
  "data": {
    "update_available": true,
    "current_version": "1.0.20",
    "latest_version": "1.0.24",
    "update_type": "force",
    "can_skip": false,
    "block_app_usage": true,
    "force_update_message": "Critical security update required",
    "release_notes": "Critical security patches",
    "download_url": "https://play.google.com/store/apps/details?id=com.gatewayreports.messenger",
    "direct_download_url": "https://example.com/gateway-academy-1.0.24.apk",
    "apk_size_mb": 45,
    "release_date": "2026-06-06",
    "min_supported_version": "1.0.24"
  }
}
```

### Test Cases

#### ✅ Test 1: Check if Current Version is Latest
```bash
curl --location 'http://localhost:8000/api/app/version-check?current_version=1.0.24'
```

#### ✅ Test 2: Check if Update Available (Optional)
```bash
curl --location 'http://localhost:8000/api/app/version-check?current_version=1.0.23'
```

#### ✅ Test 3: Check if Update Available (Forced)
```bash
curl --location 'http://localhost:8000/api/app/version-check?current_version=1.0.20'
```

---

## 🧪 COMPLETE TESTING WORKFLOW

### Step 1: Authenticate
```bash
# Get token
TOKEN=$(curl -s --location 'http://localhost:8000/api/login' \
--header 'Content-Type: application/json' \
--data-raw '{
  "email": "teacher@example.com",
  "password": "password"
}' | jq -r '.token')

echo "Token: $TOKEN"
```

### Step 2: Send Batch Messages
```bash
curl --location 'http://localhost:8000/api/messages/batch-send' \
--header "Authorization: Bearer $TOKEN" \
--header 'Content-Type: application/json' \
--data-raw '{
  "messages": [
    {"temp_id": "m1", "chat_id": 1, "chat_type": "group", "type": "text", "message": "Message 1"},
    {"temp_id": "m2", "chat_id": 1, "chat_type": "group", "type": "text", "message": "Message 2"}
  ]
}' | jq
```

### Step 3: Sync Messages
```bash
curl --location "http://localhost:8000/api/messages/sync?chat_id=1&chat_type=group&since=2026-06-01T00:00:00Z" \
--header "Authorization: Bearer $TOKEN" | jq
```

### Step 4: Sync Chats
```bash
curl --location "http://localhost:8000/api/chats/sync?since=2026-06-01T00:00:00Z" \
--header "Authorization: Bearer $TOKEN" | jq
```

### Step 5: Mark as Read
```bash
curl --location 'http://localhost:8000/api/messages/batch-read' \
--header "Authorization: Bearer $TOKEN" \
--header 'Content-Type: application/json' \
--data-raw '{
  "message_ids": [1, 2, 3],
  "chat_id": 1,
  "chat_type": "group"
}' | jq
```

### Step 6: Check Queue Status
```bash
curl --location 'http://localhost:8000/api/sync/queue-status' \
--header "Authorization: Bearer $TOKEN" | jq
```

### Step 7: Check App Version
```bash
curl --location 'http://localhost:8000/api/app/version-check?current_version=1.0.23' | jq
```

---

## 📋 ERROR RESPONSE EXAMPLES

### Unauthorized (401)
```json
{
  "message": "Unauthenticated."
}
```

### Permission Denied (403)
```json
{
  "success": false,
  "error": {
    "code": "PERMISSION_DENIED",
    "message": "No permission to send message"
  }
}
```

### Not Found (404)
```json
{
  "success": false,
  "error": {
    "code": "CHAT_NOT_FOUND",
    "message": "Chat with ID 999 not found or you don't have access"
  }
}
```

### Validation Error (422)
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The chat_type field is required."
  }
}
```

### Server Error (500)
```json
{
  "success": false,
  "error": {
    "code": "SERVER_ERROR",
    "message": "An unexpected error occurred"
  }
}
```

---

## 💡 QUICK TIPS FOR POSTMAN

### 1. Import Environment Variables
```json
{
  "id": "sync_api_env",
  "name": "Sync API Testing",
  "values": [
    {
      "key": "baseUrl",
      "value": "http://localhost:8000/api"
    },
    {
      "key": "token",
      "value": "YOUR_TOKEN_HERE"
    }
  ]
}
```

### 2. Use Tests to Extract Token
```javascript
// After login request
var jsonData = pm.response.json();
pm.environment.set("token", jsonData.token);
```

### 3. Use Pre-request Scripts
```javascript
// Set timestamp for API 2 & 3
var now = new Date();
pm.environment.set("since", now.toISOString());
```

### 4. Validate Responses
```javascript
pm.test("Response is successful", function() {
  pm.response.to.have.status(200);
  var jsonData = pm.response.json();
  pm.expect(jsonData.success).to.be.true;
});
```

---

## 🚀 POSTMAN COLLECTION JSON

Save this as `Sync-APIs.postman_collection.json` and import in Postman:

```json
{
  "info": {
    "name": "Sync APIs Collection",
    "description": "All 6 new offline-sync APIs",
    "version": "1.0.0"
  },
  "item": [
    {
      "name": "API 1 - Batch Send",
      "request": {
        "method": "POST",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{token}}"
          },
          {
            "key": "Content-Type",
            "value": "application/json"
          }
        ],
        "body": {
          "mode": "raw",
          "raw": "{\"messages\":[{\"temp_id\":\"m1\",\"chat_id\":1,\"chat_type\":\"group\",\"type\":\"text\",\"message\":\"Test message\",\"firebase_key\":\"key1\"}]}"
        },
        "url": {
          "raw": "{{baseUrl}}/messages/batch-send",
          "host": ["{{baseUrl}}"],
          "path": ["messages", "batch-send"]
        }
      }
    },
    {
      "name": "API 2 - Sync Messages",
      "request": {
        "method": "GET",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{token}}"
          }
        ],
        "url": {
          "raw": "{{baseUrl}}/messages/sync?chat_id=1&chat_type=group&since=2026-06-01T00:00:00Z",
          "host": ["{{baseUrl}}"],
          "path": ["messages", "sync"],
          "query": [
            {"key": "chat_id", "value": "1"},
            {"key": "chat_type", "value": "group"},
            {"key": "since", "value": "2026-06-01T00:00:00Z"}
          ]
        }
      }
    },
    {
      "name": "API 3 - Sync Chats",
      "request": {
        "method": "GET",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{token}}"
          }
        ],
        "url": {
          "raw": "{{baseUrl}}/chats/sync?since=2026-06-01T00:00:00Z",
          "host": ["{{baseUrl}}"],
          "path": ["chats", "sync"],
          "query": [
            {"key": "since", "value": "2026-06-01T00:00:00Z"}
          ]
        }
      }
    },
    {
      "name": "API 4 - Batch Mark as Read",
      "request": {
        "method": "POST",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{token}}"
          },
          {
            "key": "Content-Type",
            "value": "application/json"
          }
        ],
        "body": {
          "mode": "raw",
          "raw": "{\"message_ids\":[1,2,3],\"chat_id\":1,\"chat_type\":\"group\"}"
        },
        "url": {
          "raw": "{{baseUrl}}/messages/batch-read",
          "host": ["{{baseUrl}}"],
          "path": ["messages", "batch-read"]
        }
      }
    },
    {
      "name": "API 5 - Queue Status",
      "request": {
        "method": "GET",
        "header": [
          {
            "key": "Authorization",
            "value": "Bearer {{token}}"
          }
        ],
        "url": {
          "raw": "{{baseUrl}}/sync/queue-status",
          "host": ["{{baseUrl}}"],
          "path": ["sync", "queue-status"]
        }
      }
    },
    {
      "name": "API 6 - Check App Version",
      "request": {
        "method": "GET",
        "header": [],
        "url": {
          "raw": "{{baseUrl}}/app/version-check?current_version=1.0.23",
          "host": ["{{baseUrl}}"],
          "path": ["app", "version-check"],
          "query": [
            {"key": "current_version", "value": "1.0.23"}
          ]
        }
      }
    }
  ]
}
```

---

## ✅ TESTING CHECKLIST

- [ ] API 1 works with 3 messages
- [ ] API 1 works with 50 messages
- [ ] API 1 handles duplicates correctly
- [ ] API 1 validates permissions
- [ ] API 2 returns new messages
- [ ] API 2 tracks deleted messages
- [ ] API 2 tracks edited messages
- [ ] API 3 separates new vs updated chats
- [ ] API 3 shows unread counts
- [ ] API 4 marks group messages as read
- [ ] API 4 marks direct messages as read
- [ ] API 5 shows pending message count
- [ ] API 6 shows update available
- [ ] API 6 shows forced update
- [ ] All APIs return proper timestamps
- [ ] Error handling works correctly

---

**Ready to test! Import the collection in Postman and start testing!** ✅
