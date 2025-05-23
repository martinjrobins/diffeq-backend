use axum::{
    body::StreamBody,
    extract,
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Router,
};
use diffsl::compile_text;
use hyper::Method;
use serde::{Deserialize, Serialize};
use std::{env::temp_dir, net::SocketAddr, path::Path};
use tokio_util::io::ReaderStream;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();
    let app = app();
    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

fn app() -> Router {
    let cors = CorsLayer::new()
        // allow `GET` and `POST` when accessing the resource
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        // allow requests from any origin
        .allow_origin(Any)
        .allow_headers(vec![header::ACCEPT, header::CONTENT_TYPE]);
    Router::new()
        .route("/", get(hello_world))
        .route("/compile", post(compile))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
}

#[derive(Deserialize, Serialize, Debug)]
struct CompileRequest {
    text: String,
    name: String,
}

async fn hello_world() -> &'static str {
    "Hello, World!"
}

async fn compile(
    extract::Json(payload): extract::Json<CompileRequest>,
) -> Result<Response, AppError> {
    let filepath = temp_dir().join("model.wasm");
    let filename = filepath.into_os_string().into_string().unwrap();
    let options = diffsl::CompilerOptions {
        bitcode_only: false,
        wasm: true,
        standalone: false,
    };
    compile_text(
        &payload.text,
        filename.as_str(),
        &payload.name,
        options,
        true,
    )?;

    let file = tokio::fs::File::open(Path::new(filename.as_str())).await?;

    let stream = ReaderStream::new(file);

    let body = StreamBody::new(stream);

    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, "application/wasm".parse().unwrap());

    Ok((headers, body).into_response())
}

// Make our own error that wraps `anyhow::Error`.
struct AppError(anyhow::Error);

// Tell axum how to convert `AppError` into a response.
impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        (StatusCode::INTERNAL_SERVER_ERROR, self.0.to_string()).into_response()
    }
}

// This enables using `?` on functions that return `Result<_, anyhow::Error>` to turn them into
// `Result<_, AppError>`. That way you don't need to do that manually.
impl<E> From<E> for AppError
where
    E: Into<anyhow::Error>,
{
    fn from(err: E) -> Self {
        Self(err.into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use tokio::io::AsyncWriteExt;
    use tower::ServiceExt;

    #[tokio::test]
    async fn hello() {
        let app = app();

        // `Router` implements `tower::Service<Request<Body>>` so we can
        // call it like any tower service, no need to run an HTTP server.
        let response = app
            .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
        assert_eq!(&body[..], b"Hello, World!");
    }

    #[tokio::test]
    async fn discrete_logistic_model() {
        let text = String::from(
            "
            in = [r, k]
            r { 1 }
            k { 1 }
            u_i {
                y = 1,
                z = 0,
            }
            dudt_i {
                dydt = 0,
                dzdt = 0,
            }
            F_i {
                dydt,
                0,
            }
            G_i {
                (r * y) * (1 - (y / k)),
                (2 * y) - z,
            }
            out_i {
                y,
                z,
            }
        ",
        );
        let body = CompileRequest {
            text,
            name: String::from("discrete_logistic_model"),
        };
        let request = Request::builder()
            .uri("/compile")
            .method("POST")
            .header("content-type", "application/json")
            .body(Body::from(serde_json::to_string(&body).unwrap()))
            .unwrap();

        let app = app();
        let response = app.oneshot(request).await.unwrap();

        let status = response.status();
        let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let filename = "model.wasm";
        let mut file = tokio::fs::File::create(filename).await.unwrap();
        file.write_all(&body).await.unwrap();

        if status != StatusCode::OK {
            println!("Error recieved: {:?}", body);
        }

        assert_eq!(status, StatusCode::OK);
    }
}
