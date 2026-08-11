package lib

import (
	"fmt"
	"html/template"
	"log"
	"net/http"
	"strconv"
)

type ErrorPageData struct {
	Title string
	Img   string
	Text1 string
	Text2 string
}

func ErrorPageHandler(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	if code == "" {
		code = "404"
	}
	code_int, err := strconv.ParseInt(code, 10, 0)
	if err != nil {
		fmt.Fprintf(w, "%s", err.Error())
		return
	}
	if code_int > 700 {
		code_int = 700
	}
	w.WriteHeader(int(code_int))
	img, title, text1, text2 := "", "", "", ""
	switch code_int {
	case 400:
		img = "/static/images/Error.png"
		title = "Uh Oh!"
		text1 = "Something's off with that request. Try double-checking your input."
		text2 = "HTTP_Bad_Request"
	case 401:
		img = "/static/images/Error.png"
		title = "Uh Oh!"
		text1 = "Looks like you're not signed in, let's fix that!"
		text2 = "HTTP_Unauthorized"
	case 403:
		img = "/static/images/Error.png"
		title = "Access Denied!"
		text1 = "You don't have permission to view this page. Need help?"
		text2 = "HTTP_Forbidden"
	case 405:
		img = "/static/images/Erro2.png"
		title = "Access Denied!"
		text1 = "Something with that request wasnt quite right. Did you access it correctly?"
		text2 = "HTTP_Method_Not_Allowed"
	case 409:
		img = "/static/images/Erro2.png"
		title = "CONFLICTED!"
		text1 = "Something conflicted with that request. Try double-checking your input."
		text2 = "HTTP_Conflict"
	case 418:
		img = "/static/images/Erro2.png"
		title = "I'm a teapot!"
		text1 = "I can't make coffee, I'm a teapot."
		text2 = "HTTP_Im_a_teapot"
	case 429:
		img = "/static/images/Erro2.png"
		title = "Slow down please."
		text1 = "You are sending too many requests!"
		text2 = "HTTP_Too_Many_Requests"
	case 500:
		img = "/static/images/Error.png"
		title = "Uh oh!"
		text1 = "Looks like our servers hit a snag. We’re working on it!"
		text2 = "HTTP_Internal_Server_Error"
	case 502:
		img = "/static/images/bad_gateway.png"
		title = "Uh oh!"
		text1 = "The connection got a bit messy. Try refreshing."
		text2 = "HTTP_Bad_Gateway"
	case 503:
		img = "/static/images/Error.png"
		title = "Something went wrong"
		text1 = "We’re taking a quick nap. Check back soon!"
		text2 = "HTTP_Service_Unavailable"
	default:
		img = "/static/images/Erro2.png"
		title = "Page not found."
		text1 = "Looks like this page wandered off. Maybe check the URL?"
		text2 = "HTTP_Page_Not_Found"
	}
	tmpl, err := template.ParseFiles("templates/request_error.html")
	if err != nil {
		log.Fatal(err)
	}
	tmpl.Execute(w, ErrorPageData{
		Title: title,
		Img:   img,
		Text1: text1,
		Text2: text2,
	})
}
