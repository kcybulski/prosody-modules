if(typeof converse == 'undefined') {
	var div = document.createElement("div");
	var noscript = document.getElementsByTagName("noscript")[0];
	div.innerHTML = noscript.innerText;
	document.body.appendChild(div);
} else {
	converse.initialize(%s);
}
