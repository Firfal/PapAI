package com.quentin.papai.aidant

import org.json.JSONArray
import org.json.JSONObject

fun cleanText(value: String?): String = value?.trim()?.takeUnless { it.equals("null", ignoreCase = true) }.orEmpty()

fun JSONObject.text(key: String): String = cleanText(opt(key) as? String)

fun JSONArray.text(index: Int): String = cleanText(opt(index) as? String)
