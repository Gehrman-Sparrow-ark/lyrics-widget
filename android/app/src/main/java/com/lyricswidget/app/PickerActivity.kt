package com.lyricswidget.app

import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.color.MaterialColors

/** Pick lyrics for the current song, or search by hand. Opened from the card's list button. */
class PickerActivity : AppCompatActivity() {
    private lateinit var input: EditText
    private lateinit var autoBtn: MaterialButton
    private lateinit var info: TextView
    private lateinit var list: ListView
    private val listener: () -> Unit = { refresh() }

    private fun color(attr: Int): Int = MaterialColors.getColor(this, attr, 0xFF888888.toInt())
    private val onSurface get() = color(com.google.android.material.R.attr.colorOnSurface)
    private val primary get() = color(androidx.appcompat.R.attr.colorPrimary)

    private val adapter = object : BaseAdapter() {
        override fun getCount() = LyricsStore.cands.size
        override fun getItem(position: Int): Any = LyricsStore.cands[position]
        override fun getItemId(position: Int) = position.toLong()
        override fun getView(position: Int, convertView: View?, parent: ViewGroup?): View {
            val c = LyricsStore.cands[position]
            val row = LinearLayout(this@PickerActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), dp(12), dp(12), dp(12))
                if (position == LyricsStore.curIndex) setBackgroundColor(primary.withAlpha(0.18f))
            }
            row.addView(TextView(this@PickerActivity).apply {
                text = c.source
                textSize = 12f
                setTextColor(primary)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            }, LinearLayout.LayoutParams(dp(64), ViewGroup.LayoutParams.WRAP_CONTENT))
            row.addView(TextView(this@PickerActivity).apply {
                text = (if (c.artist.isNotEmpty()) c.artist + " - " else "") + c.title
                textSize = 14f
                maxLines = 2
                setTextColor(onSurface)
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(TextView(this@PickerActivity).apply {
                text = (if (c.duration > 0) fmtTime(c.duration) else "") +
                    (if (c.source == "local") "" else "  ${Math.round(c.score * 100)}%")
                textSize = 12f
                setTextColor(onSurface.withAlpha(0.6f))
            })
            return row
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Prefs.init(this)
        LyricsStore.init(this)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(8))
        }
        root.addView(TextView(this).apply {
            text = "Choose lyrics"
            textSize = 18f
            setTextColor(onSurface)
        })
        root.addView(TextView(this).apply {
            text = (LyricsStore.title + if (LyricsStore.artist.isNotEmpty()) " - " + LyricsStore.artist else "")
            textSize = 13f
            maxLines = 1
            setTextColor(onSurface.withAlpha(0.65f))
        })

        val searchRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        input = EditText(this).apply {
            hint = "Artist and title"
            setSingleLine()
            imeOptions = EditorInfo.IME_ACTION_SEARCH
            setOnEditorActionListener { _, _, _ -> submit(); true }
        }
        searchRow.addView(input, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        autoBtn = MaterialButton(this, null, com.google.android.material.R.attr.materialButtonOutlinedStyle).apply {
            text = "Auto"
            setOnClickListener { input.setText(""); LyricsStore.autoSearch() }
        }
        searchRow.addView(autoBtn)
        searchRow.addView(MaterialButton(this).apply {
            text = "Search"
            setOnClickListener { submit() }
        })
        root.addView(searchRow)

        info = TextView(this).apply {
            textSize = 13f
            setPadding(0, dp(8), 0, dp(4))
            setTextColor(onSurface.withAlpha(0.7f))
        }
        root.addView(info)

        list = ListView(this).apply {
            adapter = this@PickerActivity.adapter
            setOnItemClickListener { _, _, pos, _ ->
                if (LyricsStore.pick(pos)) finish()
            }
        }
        root.addView(list, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)

        val dm = resources.displayMetrics
        window.setLayout((dm.widthPixels * 0.94f).toInt(), (dm.heightPixels * 0.78f).toInt())
    }

    private fun submit() {
        val q = input.text.toString().trim()
        if (q.isNotEmpty()) LyricsStore.search(q)
    }

    override fun onStart() {
        super.onStart()
        LyricsStore.addListener(listener)
        LyricsStore.setPickerOpen(true)
        refresh()
    }

    override fun onStop() {
        LyricsStore.removeListener(listener)
        LyricsStore.setPickerOpen(false)
        super.onStop()
    }

    private fun refresh() {
        autoBtn.visibility = if (LyricsStore.customQuery.isNotEmpty()) View.VISIBLE else View.GONE
        info.text = when {
            LyricsStore.cands.isEmpty() && LyricsStore.busy -> "Searching…"
            LyricsStore.cands.isEmpty() -> "Nothing found. Try the search box above."
            LyricsStore.busy -> "Searching for more…"
            else -> "Tap a result to use it. It is saved on this phone."
        }
        adapter.notifyDataSetChanged()
    }
}
